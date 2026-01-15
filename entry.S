# xv6 内核从本文件开始执行。
# 该文件与内核 C 代码一起链接，因此可以直接引用 main() 等内核符号。
# bootloader（bootasm.S + bootmain.c）在完成内核加载后，
# 会跳转到 entry 这个符号开始执行。

#include "asm.h"
#include "memlayout.h"
#include "mmu.h"
#include "param.h"

# -------------------------------
# Multiboot header
# -------------------------------
# 提供给 Multiboot 兼容的引导器（如 GRUB）使用。
# xv6 默认并不通过 GRUB 启动，但保留该头部以支持 Multiboot。

.p2align 2               # 按 4 字节对齐
.text
.globl multiboot_header
multiboot_header:
  # magic number：Multiboot 标识
  # flags：功能标志（此处为 0）
  # checksum：magic + flags + checksum == 0
  # 用于让引导器校验该内核是否为合法 Multiboot 内核
  #define magic 0x1badb002
  #define flags 0
  .long magic
  .long flags
  .long (-magic-flags)

# --------------------------------
# ELF 入口点 _start
# --------------------------------
# ELF 文件的入口符号。
# 在开启分页之前，使用物理地址执行，
# 因此 _start 被设置为 entry 的物理地址。

.globl _start
_start = V2P_WO(entry)

# --------------------------------
# entry：内核真正的执行起点
# --------------------------------
# 此时状态：
# - CPU 已处于 32-bit protected mode
# - 分页（paging）尚未开启
# - 正在 boot CPU 上执行

.globl entry
entry:
  # 开启 Page Size Extension（PSE）
  # 允许使用 4MB 大页，简化早期页表设置
  movl    %cr4, %eax
  orl     $(CR4_PSE), %eax
  movl    %eax, %cr4

  # 设置页目录基址寄存器 CR3
  # entrypgdir 是早期内核使用的页目录
  movl    $(V2P_WO(entrypgdir)), %eax
  movl    %eax, %cr3

  # 开启分页机制（Paging）
  # CR0_PG：启用分页
  # CR0_WP：写保护（防止内核错误写只读页）
  movl    %cr0, %eax
  orl     $(CR0_PG|CR0_WP), %eax
  movl    %eax, %cr0

  # 设置内核栈指针
  # stack 是内核为 boot CPU 预留的栈空间
  # 栈从高地址向低地址增长
  movl $(stack + KSTACKSIZE), %esp

  # 跳转到内核 C 语言入口 main()
  # 使用间接跳转是因为：
  # 直接 jump 会生成 PC-relative 指令，
  # 在分页开启、地址映射改变后可能不正确
  mov $main, %eax
  jmp *%eax

# --------------------------------
# 为 boot CPU 分配内核栈空间
# --------------------------------
# .comm 定义一个未初始化的全局符号
# stack：栈底
# 大小：KSTACKSIZE（一个内核栈）
.comm stack, KSTACKSIZE
