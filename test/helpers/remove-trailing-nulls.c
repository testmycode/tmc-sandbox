
#include <stdio.h>
#include <string.h>

#define BUF_SIZE (64*1024)

int main()
{
    char buf[BUF_SIZE];
    memset(&buf, 0, BUF_SIZE*sizeof(char));
    while (1) {
        int amt_read = fread(buf, sizeof(char), BUF_SIZE, stdin);
        int nonnulls = 0;
        int i;
        for (i = 0; i < amt_read; ++i) {
            if (buf[i] == '\0') {
              break;
            }
            nonnulls += 1;
        }
        if (nonnulls > 0) {
            fwrite(buf, sizeof(char), nonnulls, stdout);
        } else {
            break;
        }
    }
    
    fclose(stdout);
    
    if (ferror(stdin)) {
      return 1;
    } else {
      return 0;
    }
}
