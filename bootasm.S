#include "asm.h"
#include "memlayout.h"
#include "mmu.h"

# bootasm.S：引导阶段（bootloader）第一段代码
# BIOS 会把磁盘第 1 个扇区（512B）加载到物理地址 0x7c00，
# 并在 16-bit real mode 下从这里开始执行（%cs:%ip = 0000:7c00）

.code16                 # 生成 16-bit 机器码（real mode）
.globl start
start:
  cli                   # 关闭中断：BIOS 默认开中断，启动阶段避免被打断

  # 将段寄存器清零：使 DS/ES/SS 指向 0 段（实模式下靠段:偏移寻址）
  xorw    %ax, %ax      # %ax = 0
  movw    %ax, %ds      # DS = 0（data segment）
  movw    %ax, %es      # ES = 0（extra segment）
  movw    %ax, %ss      # SS = 0（stack segment）

  # 开启 A20：早期 PC 会让地址线 A20 关闭，导致超过 1MB 会回绕。
  # 为了能访问 1MB 以上内存，需要打开 A20。
seta20.1:
  inb     $0x64, %al    # 读键盘控制器状态端口 0x64
  testb   $0x2, %al     # 检查 busy 位（输入缓冲满）
  jnz     seta20.1      # busy 就等待

  movb    $0xd1, %al    # 命令：写输出端口
  outb    %al, $0x64

seta20.2:
  inb     $0x64, %al
  testb   $0x2, %al
  jnz     seta20.2

  movb    $0xdf, %al    # 0xdf：设置 A20 使能
  outb    %al, $0x60    # 写到端口 0x60（键盘控制器数据端口）

  # 从 real mode 切到 32-bit protected mode
  # 使用一个“临时 GDT”，让线性地址=物理地址（identity mapping），
  # 这样切换时内存映射不会突然改变。
  lgdt    gdtdesc       # 加载 GDT 描述符（界限+基址）
  movl    %cr0, %eax
  orl     $CR0_PE, %eax # CR0.PE=1：开启保护模式
  movl    %eax, %cr0

  # 关键：用 long jump 刷新流水线，并加载新的 CS 选择子，
  # 正式进入 32-bit 代码段执行。
  ljmp    $(SEG_KCODE<<3), $start32

.code32                  # 从这里开始生成 32-bit 机器码（protected mode）
start32:
  # 设置保护模式下的数据段寄存器（使用平坦段：base=0, limit=4GB）
  movw    $(SEG_KDATA<<3), %ax
  movw    %ax, %ds
  movw    %ax, %es
  movw    %ax, %ss

  # FS/GS 先清零：暂时不用
  movw    $0, %ax
  movw    %ax, %fs
  movw    %ax, %gs

  # 建立临时栈，并进入 C 代码 bootmain()
  # bootmain 负责从磁盘读取内核 ELF，并跳转到内核入口 entry.S
  movl    $start, %esp   # 临时栈顶（xv6 这样写是简化做法）
  call    bootmain

  # 正常情况下 bootmain 不会返回。
  # 如果返回：输出到 Bochs 端口触发断点，然后死循环。
  movw    $0x8a00, %ax
  movw    %ax, %dx
  outw    %ax, %dx
  movw    $0x8ae0, %ax
  outw    %ax, %dx

spin:
  jmp     spin


# Bootstrap GDT：三个段描述符
.p2align 1
gdt:
  SEG_NULLASM                           # 空段（必须有）
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff) # code seg：可执行/可读
  SEG_ASM(STA_W, 0x0, 0xffffffff)       # data seg：可写

gdtdesc:
  .word   (gdtdesc - gdt - 1)           # GDT 大小 - 1
  .long   gdt                           # GDT 的线性地址


# ------------------------------------------------------------
# Task3 helper: vgaprint(void *dst, const char *s)
# Minimal VGA output: write string to dst in VGA memory.
# cdecl args: dst at 4(%esp), s at 8(%esp)
# ------------------------------------------------------------
.globl vgaprint
vgaprint:
  movl  4(%esp), %edi         # dst
  movl  8(%esp), %esi         # s
1:
  lodsb
  testb %al, %al
  jz    2f
  movb  $0x07, %ah
  stosw
  jmp   1b
2:
  ret





