#include "sender.hpp"

#include <algorithm>
#include <cstring>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
using socket_t = SOCKET;
static const socket_t kInvalid = INVALID_SOCKET;
static void CloseSocket(socket_t s) { closesocket(s); }
#else
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
using socket_t = int;
static const socket_t kInvalid = -1;
static void CloseSocket(socket_t s) { close(s); }
#endif

namespace ma3 {

struct UdpSocket::Impl {
  socket_t sock = kInvalid;
  sockaddr_storage addr{};
  socklen_t addr_len = 0;
  int family = 0;
};

UdpSocket::UdpSocket() : impl_(new Impl) {
#ifdef _WIN32
  WSADATA wsa;
  WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
}

UdpSocket::~UdpSocket() {
  if (impl_->sock != kInvalid) CloseSocket(impl_->sock);
#ifdef _WIN32
  WSACleanup();
#endif
}

bool UdpSocket::SetTarget(const std::string& host, int port) {
  if (port <= 0 || port > 65535 || host.empty()) return false;
  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_DGRAM;
  addrinfo* res = nullptr;
  if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &res) != 0 || !res) return false;
  socket_t s = socket(res->ai_family, SOCK_DGRAM, 0);
  if (s == kInvalid) {
    freeaddrinfo(res);
    return false;
  }
  if (impl_->sock != kInvalid) CloseSocket(impl_->sock);
  impl_->sock = s;
  std::memcpy(&impl_->addr, res->ai_addr, res->ai_addrlen);
  impl_->addr_len = socklen_t(res->ai_addrlen);
  impl_->family = res->ai_family;
  freeaddrinfo(res);
  return true;
}

bool UdpSocket::Send(const std::vector<uint8_t>& packet) {
  if (impl_->sock == kInvalid || packet.empty()) return false;
  auto n = sendto(impl_->sock, reinterpret_cast<const char*>(packet.data()), int(packet.size()), 0,
                  reinterpret_cast<const sockaddr*>(&impl_->addr), impl_->addr_len);
  return n == decltype(n)(packet.size());
}

Sender::Sender() : thread_([this] { Run(); }) {}

Sender::~Sender() {
  stop_ = true;
  if (thread_.joinable()) thread_.join();
}

bool Sender::SetTarget(const std::string& host, int port) {
  std::lock_guard<std::mutex> lock(socket_mutex_);
  return socket_.SetTarget(host, port);
}

bool Sender::Enqueue(const std::vector<uint8_t>* packet, Clock::time_point due) {
  const size_t head = head_.load(std::memory_order_relaxed);
  const size_t next = (head + 1) % kCapacity;
  if (next == tail_.load(std::memory_order_acquire)) {
    dropped_.fetch_add(1, std::memory_order_relaxed);
    return false;
  }
  ring_[head] = {packet, due};
  head_.store(next, std::memory_order_release);
  return true;
}

bool Sender::SendNow(const std::vector<uint8_t>& packet) {
  std::lock_guard<std::mutex> lock(socket_mutex_);
  bool ok = socket_.Send(packet);
  if (ok) sent_.fetch_add(1);
  return ok;
}

void Sender::Run() {
  while (!stop_) {
    // Drain the ring into the pending list.
    size_t tail = tail_.load(std::memory_order_relaxed);
    while (tail != head_.load(std::memory_order_acquire)) {
      pending_.push_back(ring_[tail]);
      tail = (tail + 1) % kCapacity;
      tail_.store(tail, std::memory_order_release);
    }
    // Send everything that is due, in time order.
    const auto now = Clock::now();
    std::stable_sort(pending_.begin(), pending_.end(),
                     [](const Item& a, const Item& b) { return a.due < b.due; });
    size_t done = 0;
    while (done < pending_.size() && pending_[done].due <= now) {
      SendNow(*pending_[done].packet);
      ++done;
    }
    pending_.erase(pending_.begin(), pending_.begin() + long(done));
    std::this_thread::sleep_for(std::chrono::microseconds(500));
  }
}

}  // namespace ma3
