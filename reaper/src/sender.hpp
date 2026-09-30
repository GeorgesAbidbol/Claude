// UDP sending on a background thread. The audio thread only pushes into a
// lock-free single-producer/single-consumer queue; the network call happens
// on the sender thread, at the requested time.
#pragma once

#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ma3 {

class UdpSocket {
 public:
  UdpSocket();
  ~UdpSocket();
  // Resolves host:port. Returns false (and keeps the old target) on failure.
  bool SetTarget(const std::string& host, int port);
  bool Send(const std::vector<uint8_t>& packet);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

class Sender {
 public:
  using Clock = std::chrono::steady_clock;

  Sender();
  ~Sender();

  bool SetTarget(const std::string& host, int port);

  // Audio thread: queue a packet (not copied: it must outlive the send, which
  // the owner guarantees by keeping retired schedules alive for a while).
  // Returns false if the queue is full.
  bool Enqueue(const std::vector<uint8_t>* packet, Clock::time_point due);

  // Main thread: send now (tests, one-shot commands).
  bool SendNow(const std::vector<uint8_t>& packet);

  uint64_t sent() const { return sent_.load(); }
  uint64_t dropped() const { return dropped_.load(); }

 private:
  struct Item {
    const std::vector<uint8_t>* packet;
    Clock::time_point due;
  };
  static constexpr size_t kCapacity = 4096;

  void Run();

  std::array<Item, kCapacity> ring_{};
  std::atomic<size_t> head_{0}, tail_{0};
  std::vector<Item> pending_;  // sender thread only
  std::mutex socket_mutex_;
  UdpSocket socket_;
  std::atomic<bool> stop_{false};
  std::atomic<uint64_t> sent_{0}, dropped_{0};
  std::thread thread_;
};

}  // namespace ma3
