void _start(void)
{
	register long nr asm("x8") = 142;
	register long magic1 asm("x0") = 0xfee1dead;
	register long magic2 asm("x1") = 672274793;
	register long cmd asm("x2") = 0xa1b2c3d4;
	register const char *arg asm("x3") = "bootloader";

	asm volatile("svc 0" : : "r"(nr), "r"(magic1), "r"(magic2), "r"(cmd), "r"(arg) : "memory");

	for (;;)
		;
}
