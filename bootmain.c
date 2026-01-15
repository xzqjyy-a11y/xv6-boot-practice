// Boot loader.
//
// bootmain.c 是 bootloader 的第二阶段代码，
// 与 bootasm.S 一起构成磁盘第 1 个扇区的启动程序。
// 此时 CPU 已由 bootasm.S 切换到 32-bit protected mode。
//
// bootmain() 的主要任务：
// 1. 从磁盘读取内核（ELF 格式）到内存
// 2. 解析 ELF 头与程序段表
// 3. 将内核各段加载到指定物理地址
// 4. 跳转到内核入口（entry.S）

#include "types.h"
#include "elf.h"
#include "x86.h"
#include "memlayout.h"

#define SECTSIZE  512   // 磁盘扇区大小（512 字节）

// 从磁盘读取 count 字节数据到物理地址 pa，
// offset 为内核文件中的字节偏移
void readseg(uchar*, uint, uint);

void
bootmain(void)
{
  struct elfhdr *elf;     // ELF 文件头指针
  struct proghdr *ph;     // 程序段头指针
  struct proghdr *eph;    // 程序段头表结束位置
  void (*entry)(void);    // 内核入口函数指针
  uchar* pa;              // 目标物理地址

  // 使用 0x10000 作为临时缓冲区，
  // 用来存放从磁盘读入的 ELF 头
  elf = (struct elfhdr*)0x10000;

  // 从磁盘读取内核的前 4096 字节（至少包含 ELF header）
  // offset = 0 表示从内核文件起始处读
  readseg((uchar*)elf, 4096, 0);

  // 检查 ELF 魔数，确认这是一个合法的 ELF 可执行文件
  if(elf->magic != ELF_MAGIC)
    return;  // 若不是 ELF，则返回，由 bootasm.S 处理错误

  // ELF 头中记录了程序段表的位置（phoff）
  // ph 指向第一个 program header
  ph = (struct proghdr*)((uchar*)elf + elf->phoff);
  eph = ph + elf->phnum;  // 程序段表结束位置

  // 依次加载每一个程序段
  for(; ph < eph; ph++){
    // paddr 指定该段应加载到的物理地址
    pa = (uchar*)ph->paddr;

    // 从磁盘读取该段对应的文件内容
    readseg(pa, ph->filesz, ph->off);

    // 若内存中段大小 > 文件大小（如 .bss），
    // 则将多余部分清零
    if(ph->memsz > ph->filesz)
      stosb(pa + ph->filesz, 0, ph->memsz - ph->filesz);
  }

  // ELF header 中记录了内核入口地址（entry）
  // 将其转换为函数指针并跳转执行
  // 注意：此调用不会返回
  entry = (void(*)(void))(elf->entry);
  entry();
}

void
waitdisk(void)
{
  // 等待磁盘准备就绪
  // 端口 0x1F7：磁盘状态寄存器
  // 0x40 表示磁盘已就绪
  while((inb(0x1F7) & 0xC0) != 0x40)
    ;
}

// 从磁盘读取一个扇区到 dst
// offset 为扇区号（LBA）
void
readsect(void *dst, uint offset)
{
  // 等待磁盘空闲
  waitdisk();

  // 向 IDE 控制器发送读扇区命令
  outb(0x1F2, 1);          // 一次读取 1 个扇区
  outb(0x1F3, offset);    // LBA 低 8 位
  outb(0x1F4, offset >> 8);
  outb(0x1F5, offset >> 16);
  outb(0x1F6, (offset >> 24) | 0xE0);  // LBA 高 4 位 + 主盘
  outb(0x1F7, 0x20);       // 命令 0x20：读扇区

  // 从数据端口读取扇区内容
  waitdisk();
  insl(0x1F0, dst, SECTSIZE/4);
}

// 从内核文件中读取 count 字节数据到物理地址 pa
// offset 为内核文件中的字节偏移
// 实际读取可能会超过 count（按整扇区读取）
void
readseg(uchar* pa, uint count, uint offset)
{
  uchar* epa;

  epa = pa + count;

  // 将 pa 向下对齐到扇区边界
  pa -= offset % SECTSIZE;

  // 将字节偏移转换为扇区号
  // 内核文件从磁盘第 1 个扇区开始（第 0 个是 boot block）
  offset = (offset / SECTSIZE) + 1;

  // 逐扇区读取，直到覆盖所需的内存区域
  for(; pa < epa; pa += SECTSIZE, offset++)
    readsect(pa, offset);
}
