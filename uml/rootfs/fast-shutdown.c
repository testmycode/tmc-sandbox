/* Brings down a transient UML really fast by skipping a lot of unnecessary stuff.
 * See halt.c in sysvinit for what is normally done. */

#include <unistd.h>
#include <sys/reboot.h>

int main()
{
	sync();
	/* No sleep(2) like halt does. According to sync()'s man page, it should be safe,
	   especially since UML's disks are virtual. */
	
	reboot(RB_POWER_OFF);
	
	return 0;
}
