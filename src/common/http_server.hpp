#pragma once

// 极简 HTTP/1.1 服务器：只实现网页控制需要的 GET/POST/OPTIONS，
// 响应后关闭连接，不支持 keep-alive。只依赖 POSIX socket，便于
// 交叉编译和自包含发布包，不引入第三方库。

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <atomic>
#include <cctype>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace tb6612 {

// 解码 %XX 和 '+'，用于查询串和表单正文。
inline std::string url_decode(const std::string& text) {
  std::string result;
  result.reserve(text.size());
  for (std::size_t i = 0; i < text.size(); ++i) {
    if (text[i] == '+') {
      result.push_back(' ');
    } else if (text[i] == '%' && i + 2 < text.size() &&
               std::isxdigit(static_cast<unsigned char>(text[i + 1])) &&
               std::isxdigit(static_cast<unsigned char>(text[i + 2]))) {
      const std::string hex = text.substr(i + 1, 2);
      result.push_back(
          static_cast<char>(std::strtol(hex.c_str(), nullptr, 16)));
      i += 2;
    } else {
      result.push_back(text[i]);
    }
  }
  return result;
}

inline std::vector<std::string> split(const std::string& text,
                                      char separator) {
  std::vector<std::string> parts;
  std::string current;
  for (const char character : text) {
    if (character == separator) {
      parts.push_back(current);
      current.clear();
    } else {
      current.push_back(character);
    }
  }
  parts.push_back(current);
  return parts;
}

// 从 JSON 文本里取 "key": number，兼容空格差异。
inline bool json_number(const std::string& text, const std::string& key,
                        double* value) {
  const std::size_t position = text.find("\"" + key + "\"");
  if (position == std::string::npos) {
    return false;
  }
  std::size_t cursor = text.find(':', position);
  if (cursor == std::string::npos) {
    return false;
  }
  ++cursor;
  while (cursor < text.size() &&
         std::isspace(static_cast<unsigned char>(text[cursor]))) {
    ++cursor;
  }
  char* end = nullptr;
  const double parsed = std::strtod(text.c_str() + cursor, &end);
  if (end == text.c_str() + cursor) {
    return false;
  }
  *value = parsed;
  return true;
}

struct HttpRequest {
  std::string method;
  std::string path;
  std::string query;
  std::string body;
  std::map<std::string, std::string> headers;

  // 头部名称按小写存放，查询未找到时返回空字符串。
  std::string header(const std::string& name) const {
    const auto it = headers.find(name);
    return it == headers.end() ? std::string{} : it->second;
  }

  std::map<std::string, std::string> query_params() const {
    std::map<std::string, std::string> params;
    for (const std::string& pair : split(query, '&')) {
      const std::size_t equal = pair.find('=');
      if (equal == std::string::npos) {
        continue;
      }
      params[url_decode(pair.substr(0, equal))] =
          url_decode(pair.substr(equal + 1));
    }
    return params;
  }

  // 单个查询参数，未找到时返回空字符串。
  std::string query_value(const std::string& name) const {
    const auto params = query_params();
    const auto it = params.find(name);
    return it == params.end() ? std::string{} : it->second;
  }
};

struct HttpResponse {
  int status = 200;
  std::string content_type = "text/plain; charset=utf-8";
  std::string body;
};

// 解析 application/x-www-form-urlencoded 或简单 JSON 里的数值字段。
// 两种格式都取 linear/angular，缺省的字段保持 0。
inline bool parse_command_values(const std::string& text, double* linear,
                                 double* angular) {
  if (linear == nullptr || angular == nullptr) {
    return false;
  }
  *linear = 0.0;
  *angular = 0.0;
  bool found = false;
  for (const std::string& pair : split(text, '&')) {
    const std::size_t equal = pair.find('=');
    if (equal == std::string::npos) {
      continue;
    }
    const std::string key = url_decode(pair.substr(0, equal));
    const std::string value = url_decode(pair.substr(equal + 1));
    if (key != "linear" && key != "angular") {
      continue;
    }
    char* end = nullptr;
    const double parsed = std::strtod(value.c_str(), &end);
    if (end == value.c_str()) {
      return false;
    }
    if (key == "linear") {
      *linear = parsed;
    } else {
      *angular = parsed;
    }
    found = true;
  }
  if (found) {
    return true;
  }
  double json_linear = 0.0;
  double json_angular = 0.0;
  const bool has_linear = json_number(text, "linear", &json_linear);
  const bool has_angular = json_number(text, "angular", &json_angular);
  if (!has_linear && !has_angular) {
    return false;
  }
  *linear = has_linear ? json_linear : 0.0;
  *angular = has_angular ? json_angular : 0.0;
  return true;
}

class HttpServer {
 public:
  using Handler = std::function<HttpResponse(const HttpRequest&)>;

  HttpServer(std::string bind_address, std::uint16_t port, Handler handler)
      : bind_address_(std::move(bind_address)),
        port_(port),
        handler_(std::move(handler)) {}

  ~HttpServer() { stop(); }

  HttpServer(const HttpServer&) = delete;
  HttpServer& operator=(const HttpServer&) = delete;

  // 绑定并监听；端口为 0 时由系统分配，port() 返回实际端口。
  bool start(std::string* error) {
    listen_fd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd_ < 0) {
      if (error != nullptr) {
        *error = std::string("socket: ") + std::strerror(errno);
      }
      return false;
    }
    int reuse = 1;
    ::setsockopt(listen_fd_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(port_);
    if (::inet_pton(AF_INET, bind_address_.c_str(), &address.sin_addr) != 1) {
      if (error != nullptr) {
        *error = "invalid bind address: " + bind_address_;
      }
      ::close(listen_fd_);
      listen_fd_ = -1;
      return false;
    }
    if (::bind(listen_fd_, reinterpret_cast<sockaddr*>(&address),
               sizeof(address)) < 0) {
      if (error != nullptr) {
        *error = std::string("bind: ") + std::strerror(errno);
      }
      ::close(listen_fd_);
      listen_fd_ = -1;
      return false;
    }
    if (::listen(listen_fd_, 16) < 0) {
      if (error != nullptr) {
        *error = std::string("listen: ") + std::strerror(errno);
      }
      ::close(listen_fd_);
      listen_fd_ = -1;
      return false;
    }
    sockaddr_in bound{};
    socklen_t length = sizeof(bound);
    if (::getsockname(listen_fd_, reinterpret_cast<sockaddr*>(&bound),
                      &length) == 0) {
      port_ = ntohs(bound.sin_port);
    }
    return true;
  }

  std::uint16_t port() const { return port_; }

  // 接受循环，阻塞直到 stop() 被调用。
  void run() {
    while (!stop_requested_) {
      const int client_fd = ::accept(listen_fd_, nullptr, nullptr);
      if (client_fd < 0) {
        if (errno == EINTR) {
          continue;
        }
        if (!stop_requested_) {
          continue;
        }
        break;
      }
      if (active_connections_ >= kMaxConnections) {
        ::close(client_fd);
        continue;
      }
      ++active_connections_;
      std::thread([this, client_fd]() {
        handle_connection(client_fd);
        --active_connections_;
      }).detach();
    }
  }

  void stop() {
    stop_requested_ = true;
    if (listen_fd_ >= 0) {
      ::shutdown(listen_fd_, SHUT_RDWR);
      ::close(listen_fd_);
      listen_fd_ = -1;
    }
  }

 private:
  static constexpr std::size_t kMaxConnections = 16;
  static constexpr std::size_t kMaxBodyBytes = 8192;
  static constexpr int kSocketTimeoutSeconds = 3;

  static std::string status_text(int status) {
    switch (status) {
      case 200:
        return "OK";
      case 204:
        return "No Content";
      case 400:
        return "Bad Request";
      case 403:
        return "Forbidden";
      case 404:
        return "Not Found";
      case 405:
        return "Method Not Allowed";
      case 500:
        return "Internal Server Error";
      default:
        return "Unknown";
    }
  }

  static bool parse_request(const std::string& raw, HttpRequest* request) {
    const std::size_t head_end = raw.find("\r\n\r\n");
    if (head_end == std::string::npos) {
      return false;
    }
    const std::string head = raw.substr(0, head_end);
    std::size_t line_end = head.find("\r\n");
    const std::string request_line =
        head.substr(0, line_end == std::string::npos ? head.size() : line_end);
    std::istringstream stream(request_line);
    std::string target;
    if (!(stream >> request->method >> target)) {
      return false;
    }
    const std::size_t question = target.find('?');
    if (question == std::string::npos) {
      request->path = url_decode(target);
    } else {
      request->path = url_decode(target.substr(0, question));
      request->query = target.substr(question + 1);
    }
    while (line_end != std::string::npos) {
      const std::size_t next_end = head.find("\r\n", line_end + 2);
      const std::string line =
          head.substr(line_end + 2,
                      next_end == std::string::npos ? std::string::npos
                                                    : next_end - line_end - 2);
      const std::size_t colon = line.find(':');
      if (colon != std::string::npos) {
        std::string name = line.substr(0, colon);
        std::string value = line.substr(colon + 1);
        while (!value.empty() &&
               (value.front() == ' ' || value.front() == '\t')) {
          value.erase(value.begin());
        }
        for (char& character : name) {
          character = static_cast<char>(
              std::tolower(static_cast<unsigned char>(character)));
        }
        request->headers[name] = value;
      }
      line_end = next_end;
    }
    return true;
  }

  static bool send_all(int fd, const std::string& data) {
    std::size_t sent = 0;
    while (sent < data.size()) {
      const ssize_t written =
          ::send(fd, data.data() + sent, data.size() - sent, MSG_NOSIGNAL);
      if (written <= 0) {
        if (written < 0 && errno == EINTR) {
          continue;
        }
        return false;
      }
      sent += static_cast<std::size_t>(written);
    }
    return true;
  }

  void handle_connection(int client_fd) {
    timeval timeout{};
    timeout.tv_sec = kSocketTimeoutSeconds;
    ::setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    ::setsockopt(client_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    std::string buffer;
    char chunk[2048];
    std::size_t head_end = std::string::npos;
    while (true) {
      const ssize_t received = ::recv(client_fd, chunk, sizeof(chunk), 0);
      if (received <= 0) {
        break;
      }
      buffer.append(chunk, static_cast<std::size_t>(received));
      head_end = buffer.find("\r\n\r\n");
      if (head_end != std::string::npos || buffer.size() >= kMaxBodyBytes) {
        break;
      }
    }
    if (head_end == std::string::npos) {
      ::close(client_fd);
      return;
    }

    HttpRequest request;
    if (!parse_request(buffer, &request)) {
      ::close(client_fd);
      return;
    }
    const std::size_t body_start = head_end + 4;
    std::size_t content_length = 0;
    const std::string length_header = request.header("content-length");
    if (!length_header.empty()) {
      content_length = static_cast<std::size_t>(
          std::strtoul(length_header.c_str(), nullptr, 10));
      if (content_length > kMaxBodyBytes) {
        content_length = kMaxBodyBytes;
      }
    }
    while (buffer.size() < body_start + content_length) {
      const ssize_t received = ::recv(client_fd, chunk, sizeof(chunk), 0);
      if (received <= 0) {
        break;
      }
      buffer.append(chunk, static_cast<std::size_t>(received));
    }
    request.body = buffer.substr(body_start, content_length);

    HttpResponse response;
    try {
      response = handler_(request);
    } catch (const std::exception&) {
      response.status = 500;
      response.content_type = "text/plain; charset=utf-8";
      response.body = "internal error";
    }

    std::string head = "HTTP/1.1 " + std::to_string(response.status) + " " +
                       status_text(response.status) + "\r\n";
    head += "Content-Type: " + response.content_type + "\r\n";
    head += "Content-Length: " + std::to_string(response.body.size()) + "\r\n";
    head += "Access-Control-Allow-Origin: *\r\n";
    head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n";
    head += "Access-Control-Allow-Headers: Content-Type, X-Car-Token\r\n";
    head += "Cache-Control: no-store\r\n";
    head += "Connection: close\r\n\r\n";
    send_all(client_fd, head);
    if (!response.body.empty()) {
      send_all(client_fd, response.body);
    }
    ::close(client_fd);
  }

  std::string bind_address_;
  std::uint16_t port_;
  Handler handler_;
  int listen_fd_ = -1;
  std::atomic<bool> stop_requested_{false};
  std::atomic<std::size_t> active_connections_{0};
};

}  // namespace tb6612
