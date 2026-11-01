#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>

#include "http_server.hpp"

namespace {

void check(bool value, const std::string& message) {
  if (!value) {
    std::cerr << "HTTP server check failed: " << message << "\n";
    std::exit(1);
  }
}

// 发送一次请求并读完整响应：服务器响应后关闭连接，读到 EOF 即结束。
std::string send_request(std::uint16_t port, const std::string& request) {
  const int fd = ::socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    return {};
  }
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_port = htons(port);
  ::inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
  if (::connect(fd, reinterpret_cast<sockaddr*>(&address),
                 sizeof(address)) < 0) {
    ::close(fd);
    return {};
  }
  ::send(fd, request.data(), request.size(), MSG_NOSIGNAL);
  std::string response;
  char buffer[1024];
  ssize_t received = 0;
  while ((received = ::recv(fd, buffer, sizeof(buffer), 0)) > 0) {
    response.append(buffer, static_cast<std::size_t>(received));
  }
  ::close(fd);
  return response;
}

}  // namespace

int main() {
  tb6612::HttpServer server(
      "127.0.0.1", 0,
      [](const tb6612::HttpRequest& request) {
        if (request.path == "/cmd") {
          std::string payload = request.body;
          if (payload.empty()) {
            payload = "linear=" + request.query_value("linear") +
                      "&angular=" + request.query_value("angular");
          }
          double linear = 0.0;
          double angular = 0.0;
          if (!tb6612::parse_command_values(payload, &linear, &angular)) {
            return tb6612::HttpResponse{400, "text/plain", "invalid"};
          }
          return tb6612::HttpResponse{
              200, "application/json",
              "linear=" + std::to_string(linear) +
                  " angular=" + std::to_string(angular)};
        }
        if (request.path == "/missing") {
          return tb6612::HttpResponse{404, "text/plain", "not found"};
        }
        return tb6612::HttpResponse{200, "text/plain",
                                    "path=" + request.path +
                                        " query=" + request.query};
      });

  std::string error;
  check(server.start(&error), "start failed: " + error);
  check(server.port() != 0, "ephemeral port not resolved");
  std::thread runner([&server]() { server.run(); });

  const std::string get = send_request(
      server.port(), "GET /hello?x=1 HTTP/1.1\r\nHost: test\r\n\r\n");
  check(get.find("200 OK") != std::string::npos, "GET status line");
  check(get.find("path=/hello query=x=1") != std::string::npos, "GET payload");
  check(get.find("Content-Type: text/plain") != std::string::npos,
        "GET content type");

  const std::string body = "linear=0.15&angular=0.8";
  const std::string post = send_request(
      server.port(),
      "POST /cmd HTTP/1.1\r\nHost: test\r\nContent-Type: "
      "application/x-www-form-urlencoded\r\nContent-Length: " +
          std::to_string(body.size()) + "\r\n\r\n" + body);
  check(post.find("200 OK") != std::string::npos, "POST status line");
  check(post.find("linear=0.150000 angular=0.800000") != std::string::npos,
        "POST payload");

  const std::string missing =
      send_request(server.port(), "GET /missing HTTP/1.1\r\n\r\n");
  check(missing.find("404 Not Found") != std::string::npos, "404 status line");

  const std::string query = send_request(
      server.port(), "GET /cmd?linear=0.25&angular=0 HTTP/1.1\r\n\r\n");
  check(query.find("200 OK") != std::string::npos, "query status line");
  check(query.find("linear=0.250000 angular=0.000000") != std::string::npos,
        "query values");

  const std::string bad = send_request(
      server.port(), "GET /cmd HTTP/1.1\r\n\r\n");
  check(bad.find("400") != std::string::npos,
        "missing command values must be rejected");

  double linear = 0.0;
  double angular = 0.0;
  check(tb6612::parse_command_values("linear=0.3&angular=-0.5", &linear,
                                     &angular),
        "form parsing");
  check(linear == 0.3 && angular == -0.5, "form values");
  check(tb6612::parse_command_values("{\"linear\":0.2,\"angular\":0.4}",
                                     &linear, &angular),
        "json parsing");
  check(linear == 0.2 && angular == 0.4, "json values");
  check(!tb6612::parse_command_values("linear=abc", &linear, &angular),
        "invalid value must be rejected");
  check(!tb6612::parse_command_values("", &linear, &angular),
        "empty payload must be rejected");

  server.stop();
  runner.join();
  return 0;
}
