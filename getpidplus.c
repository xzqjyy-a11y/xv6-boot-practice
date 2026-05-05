#include "types.h"
#include "stat.h"
#include "user.h"

int
main(void)
{
  int pid;
  int pid_plus;

  pid = getpid();
  pid_plus = getpid_plus();

  printf(1, "pid = %d\n", pid);
  printf(1, "getpid_plus = %d\n", pid_plus);

  exit();
}