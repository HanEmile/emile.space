#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_NOTES 10
#define NOTE_SIZE 0x100

void *notes[MAX_NOTES];
size_t sizes[MAX_NOTES];
void *top_chunk;

// Secret win condition
volatile unsigned int win_condition = 1234;

void win() {
    if (win_condition == 0x1337beef) {
        printf("[+] You win! Here's your flag: FLAG{heap_exploitation_master}\n");
        exit(0);
    }
}

void setup() {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stdin, NULL, _IONBF, 0);
    top_chunk = sbrk(0);
    printf("[DEBUG] Initial top chunk: %p\n", top_chunk);
    printf("[DEBUG] Address of win_condition: %p\n", (void*)&win_condition);
}

void clear_stdin() {
    int c;
    while ((c = getchar()) != '\n' && c != EOF);
}

void hexdump(void *addr, size_t count) {
    unsigned char *p = (unsigned char *)addr - 0xf;
    printf("[DEBUG] Hexdump of %p (count: %lu):\n", addr, count);
    for (size_t i = 0; i < count; i++) {
        if ((i % 8 == 0) && i!=0) printf("| ");
        if (i % 16 == 0) printf("\n%p: ", p + i);
        printf("%02x ", p[i-1]);
    }
    printf("\n");
}

void create_note() {
    int idx;
    for (idx = 0; idx < MAX_NOTES; idx++) {
        if (!notes[idx]) break;
    }
    if (idx == MAX_NOTES) {
        printf("[!] No more note slots available\n");
        return;
    }

    printf("[?] Note size: ");
    size_t size;
    if (scanf("%lx", &size) != 1) {
        printf("[!] Invalid input\n");
        clear_stdin();
        return;
    }
    clear_stdin();
    
    void *ptr = malloc(size);
    if (!ptr) {
        printf("[!] malloc failed\n");
        return;
    }
    
    printf("[DEBUG] Allocated note at %p with size %lu\n", ptr, size);
    notes[idx] = ptr;
    sizes[idx] = size;
    
    printf("[+] Note %d created\n", idx);
}

void write_note() {
    printf("[?] Note index: ");
    int idx;
    if (scanf("%d", &idx) != 1) {
        printf("[!] Invalid input\n");
        clear_stdin();
        return;
    }
    clear_stdin();
    
    if (idx < 0 || idx >= MAX_NOTES || !notes[idx]) {
        printf("[!] Invalid note index\n");
        return;
    }
    
    printf("[?] Data to write: ");
    // fgets((char *)notes[idx], sizes[idx], stdin);
    fgets((char *)notes[idx], 128, stdin);
    printf("[+] Written to note %d\n", idx);
}

void read_note() {
    printf("[?] Note index: ");
    int idx;
    if (scanf("%d", &idx) != 1) {
        printf("[!] Invalid input\n");
        clear_stdin();
        return;
    }
    clear_stdin();
    
    if (idx < 0 || idx >= MAX_NOTES || !notes[idx]) {
        printf("[!] Invalid note index\n");
        return;
    }

    printf("[DEBUG] Reading note %d at %p: %s\n", idx, notes[idx], (char*)notes[idx]);
    // hexdump(notes[idx], sizes[idx]);
    hexdump(notes[idx], (8 * sizes[idx]) + 64);
}

void delete_note() {
    printf("[?] Note index: ");
    int idx;
    if (scanf("%d", &idx) != 1) {
        printf("[!] Invalid input\n");
        clear_stdin();
        return;
    }
    clear_stdin();
    
    if (idx < 0 || idx >= MAX_NOTES || !notes[idx]) {
        printf("[!] Invalid note index\n");
        return;
    }
    
    printf("[DEBUG] Freeing note %d at %p\n", idx, notes[idx]);
    free(notes[idx]);
    notes[idx] = NULL;
    sizes[idx] = 0;
    printf("[+] Note %d deleted\n", idx);
}

int main() {
    setup();

    volatile unsigned int secret_pincode = 1337;

    printf("[DEBUG] Address of secret pincode: %p\n", (void*)&secret_pincode);
    
    while (1) {
        printf("\nNote app v1.33.7\n\n");
        printf("[1] Create Note\n");
        printf("[2] Read Note\n");
        printf("[3] Write Note\n");
        printf("[4] Delete Note\n");
        printf("[5] Exit\n");
        printf("> ");
        
        int choice;
        if (scanf("%d", &choice) != 1) {
            printf("[!] Invalid input\n");
            clear_stdin();
            continue;
        }
        clear_stdin();
        
        switch (choice) {
            case 1: create_note(); break;
            case 2: read_note(); break;
            case 3: write_note(); break;
            case 4: delete_note(); break;
            case 5: printf("[!] Exiting...\n"); exit(0);
            default: printf("[!] Invalid option\n");
        }
    }
}
