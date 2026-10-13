// selftest/smoke_stub.cpp —— 零第三方依赖的 C++ 胶水（FFI 机制自检）
//
// 这个文件**不包含 Eigen**，只用 C++ 标准库，目的是把
// "MoonBit 的 native FFI 机制是否可用" 与 "Eigen 能否编译" 解耦。
//
// 它刻意复刻 src/eigen_shim.cpp 的全部关键机制，一一对应：
//   1. extern "C" + MOONBIT_FFI_EXPORT 导出
//   2. moonbit_make_external_object 注册 finalizer 管理 C++ 对象生命周期
//   3. 抽象类型句柄 + 指针类型参数由 MoonBit 侧标 #borrow
//   4. 失败不用 nullptr，用 valid=false 的哨兵对象（抽象类型没有 null 语义）
//   5. moonbit_make_bytes + MoonBit 侧 @utf8.decode_lossy 做字符串往返
//   6. 所有 C++ 异常都挡在 ABI 边界内

#include <moonbit.h>

#include <cstdint>
#include <cstring>
#include <exception>
#include <new>
#include <string>
#include <vector>

#ifndef MOONBIT_FFI_EXPORT
#define MOONBIT_FFI_EXPORT
#endif

namespace {

thread_local std::string g_message;

struct Box {
  bool valid = true;
  std::int32_t rows = 0;
  std::int32_t cols = 0;
  std::vector<double> data;
};

/// finalize 只释放 payload 里的 C++ 对象；不得释放 self 容器本身
/// （官方 moonbit.h 注释：finalize MUST NOT drop the container itself）。
void box_finalize(void *self) {
  auto **slot = static_cast<Box **>(self);
  delete *slot;
  *slot = nullptr;
}

/// 把 C++ 对象包成 MoonBit 拥有的外部对象。
void *wrap(Box *box) {
  if (box == nullptr) {
    return nullptr;
  }
  void *obj = moonbit_make_external_object(box_finalize, sizeof(Box *));
  *static_cast<Box **>(obj) = box;
  return obj;
}

/// 错误哨兵：抽象类型没有 null 语义，所以失败也要返回一个可安全回收的对象。
Box *make_invalid() {
  try {
    auto *box = new Box();
    box->valid = false;
    return box;
  } catch (...) {
    return nullptr;
  }
}

/// UTF-8 原样搬运到 MoonBit 拥有的 Bytes（编码转换交给 MoonBit 侧的 @utf8）。
moonbit_bytes_t to_mbt_bytes(const std::string &s) {
  moonbit_bytes_t out = moonbit_make_bytes(static_cast<std::int32_t>(s.size()), 0);
  if (!s.empty()) {
    std::memcpy(out, s.data(), s.size());
  }
  return out;
}

/// 从 MoonBit 传回来的句柄取出 C++ 对象指针。
///
/// ⚠️ 必须**解引用**：句柄是 moonbit_make_external_object 返回的
/// **payload 指针**，payload 里存的才是 Box*。
/// 直接把 payload 指针 static_cast 成 Box* 会读到垃圾
/// （实测表现：rows() 返回 607 —— 那是堆指针的高 4 字节）。
/// 注意 box_finalize 里是正确的（delete *slot），两处必须保持一致。
Box *as_box(void *handle) {
  if (handle == nullptr) {
    return nullptr;
  }
  return *static_cast<Box **>(handle);
}

}  // namespace

extern "C" {

/// 构建期自检：返回 (C++ 标准版本 * 1000 + 一个标记串的长度)。
/// 预期 C++17 下为 17016（"moonbit-selftest" 有 16 个字符）。
///
/// 这是整个项目最重要的一行可执行证据：它能返回预期值，就说明
/// C++ 源文件真的被当作 C++17 编译并链接进了 MoonBit 的 native 产物。
MOONBIT_FFI_EXPORT
std::int32_t mb_smoke_probe(void) {
  const std::string marker = "moonbit-selftest";
  return static_cast<std::int32_t>((__cplusplus / 100 % 100) * 1000 +
                                   marker.size());
}

MOONBIT_FFI_EXPORT
void *mb_smoke_new(std::int32_t rows, std::int32_t cols) {
  g_message.clear();
  if (rows < 0 || cols < 0) {
    g_message = "尺寸不能为负";
    return wrap(make_invalid());
  }
  try {
    auto *box = new Box();
    box->rows = rows;
    box->cols = cols;
    box->data.assign(static_cast<std::size_t>(rows) *
                         static_cast<std::size_t>(cols),
                     0.0);
    return wrap(box);
  } catch (...) {
    g_message = "分配失败";
    return wrap(make_invalid());
  }
}

/// 返回 -1 表示无效对象 / 上一次操作失败。
MOONBIT_FFI_EXPORT
std::int32_t mb_smoke_rows(void *handle) {
  Box *box = as_box(handle);
  return (box == nullptr || !box->valid) ? -1 : box->rows;
}

MOONBIT_FFI_EXPORT
std::int32_t mb_smoke_set(void *handle, std::int32_t i, std::int32_t j,
                          double v) {
  g_message.clear();
  Box *box = as_box(handle);
  if (box == nullptr || !box->valid) {
    g_message = "无效对象";
    return 1;
  }
  if (i < 0 || j < 0 || i >= box->rows || j >= box->cols) {
    // 这个中文字面量同时是**编码往返测试**：
    // 它由 MSVC 以 UTF-8 编入（靠 cc-flags 里的 /utf-8），
    // 由 moonbit_make_bytes 原样搬到 MoonBit，
    // 再由 @utf8.decode_lossy 解码 —— 测试会拿它和 MoonBit 源码里的
    // 同名字面量比较，任何一环编码错了都会失败。
    g_message = "下标越界";
    return 1;
  }
  box->data[static_cast<std::size_t>(i) * box->cols + j] = v;
  return 0;
}

MOONBIT_FFI_EXPORT
double mb_smoke_sum(void *handle) {
  Box *box = as_box(handle);
  if (box == nullptr || !box->valid) {
    return 0.0;
  }
  double s = 0.0;
  for (double x : box->data) {
    s += x;
  }
  return s;
}

/// 上一次操作的错误信息（UTF-8 Bytes）。成功时为空。
MOONBIT_FFI_EXPORT
moonbit_bytes_t mb_smoke_message(void) { return to_mbt_bytes(g_message); }

}  // extern "C"
