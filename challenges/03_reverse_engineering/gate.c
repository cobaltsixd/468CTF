#include <stdio.h>
#include <string.h>

unsigned k(const char *s){
  unsigned h=5381; int c;
  while((c=*s++)) h=((h<<5)+h)+c;
  return h;
}

int main(){
  char buf[64];
  printf("Key: ");
  if(!fgets(buf,64,stdin)) return 1;
  buf[strcspn(buf,"\n")]=0;
  if(k(buf)==0x5A0F9F7B){
    FILE *f=fopen("/opt/ctf/flags/flag_re.txt","r");
    if(f){ char line[256]; fgets(line,256,f); puts(line); fclose(f); }
    else puts("flag file missing");
  } else {
    puts("Access denied.");
  }
  return 0;
}
