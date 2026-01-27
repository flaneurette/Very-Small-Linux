#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define MAX_FILES 10000
#define MAX_PATH 4096
#define MAX_LINE 512

typedef struct {
    char name[MAX_PATH];
    int is_dir;
} FileEntry;

struct termios orig_termios;

void disable_raw_mode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void enable_raw_mode() {
    tcgetattr(STDIN_FILENO, &orig_termios);
    atexit(disable_raw_mode);
    
    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
}

int get_key() {
    char c;
    if (read(STDIN_FILENO, &c, 1) != 1) return -1;
    
    if (c == 27) {
        char seq[3];
        if (read(STDIN_FILENO, &seq[0], 1) != 1) return 27;
        if (read(STDIN_FILENO, &seq[1], 1) != 1) return 27;
        
        if (seq[0] == '[') {
            switch (seq[1]) {
                case 'A': return 1000; // UP
                case 'B': return 1001; // DOWN
                case 'C': return 1002; // RIGHT
                case 'D': return 1003; // LEFT
            }
        }
        return 27;
    }
    return c;
}

void list_dir(const char *path, FileEntry *files, int *count) {
    DIR *dir = opendir(path);
    struct dirent *entry;
    *count = 0;
    if (!dir) {
        printf("Cannot open directory: %s\r\n", path);
        return;
    }

    while ((entry = readdir(dir)) != NULL && *count < MAX_FILES) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        strncpy(files[*count].name, entry->d_name, MAX_PATH - 1);
        files[*count].name[MAX_PATH - 1] = '\0';
        files[*count].is_dir = entry->d_type == DT_DIR;
        (*count)++;
    }

    closedir(dir);
}

int get_terminal_height() {
    struct winsize w;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == -1) {
        return 24;
    }
    return w.ws_row;
}

void read_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) {
        printf("\033[2J\033[H");
        printf("Cannot open file: %s\r\n", path);
        printf("Press any key to go back...\r\n");
        get_key();
        return;
    }

    // Count total lines
    int total_lines = 0;
    char line[MAX_LINE];
    while (fgets(line, sizeof(line), f)) {
        total_lines++;
    }
    rewind(f);

    if (total_lines == 0) {
        printf("\033[2J\033[H");
        printf("File is empty: %s\r\n", path);
        printf("Press any key to go back...\r\n");
        fclose(f);
        get_key();
        return;
    }

    // Allocate array of line pointers
    char **lines = malloc(total_lines * sizeof(char*));
    if (!lines) {
        printf("\033[2J\033[H");
        printf("Memory allocation failed!\r\n");
        printf("Press any key to go back...\r\n");
        fclose(f);
        get_key();
        return;
    }

    // Read all lines into memory
    int line_count = 0;
    while (fgets(line, sizeof(line), f) && line_count < total_lines) {
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') line[len-1] = '\0';
        
        lines[line_count] = malloc(len + 1);
        if (!lines[line_count]) {
            printf("\033[2J\033[H");
            printf("Memory allocation failed!\r\n");
            for (int j = 0; j < line_count; j++) free(lines[j]);
            free(lines);
            fclose(f);
            get_key();
            return;
        }
        strcpy(lines[line_count], line);
        line_count++;
    }
    fclose(f);

    // Display with scrolling
    int scroll_pos = 0;
    int term_height = get_terminal_height();
    int display_lines = term_height - 4;
    
    while (1) {
        printf("\033[2J\033[H");
        printf("File: %s (lines %d-%d of %d)\r\n", 
               path, scroll_pos + 1, 
               scroll_pos + display_lines > line_count ? line_count : scroll_pos + display_lines,
               line_count);
        printf("─────────────────────────────────────\r\n");
        
        for (int i = 0; i < display_lines && (scroll_pos + i) < line_count; i++) {
            printf("%s\r\n", lines[scroll_pos + i]);
        }
        
        printf("─────────────────────────────────────\r\n");
        printf("↑↓ scroll | Space/b page | g/G top/bottom | q quit\r\n");
        
        int key = get_key();
        if (key == 'q' || key == 'Q') break;
        
        // Arrow key scrolling
        if (key == 1000 && scroll_pos > 0) scroll_pos--;
        if (key == 1001 && scroll_pos < total_lines - display_lines) scroll_pos++;
        
        // Page down with space
        if (key == ' ' && scroll_pos < total_lines - display_lines) {
            scroll_pos += display_lines;
            if (scroll_pos > total_lines - display_lines) 
                scroll_pos = total_lines - display_lines;
        }
        // Page up with 'b'
        if (key == 'b' && scroll_pos > 0) {
            scroll_pos -= display_lines;
            if (scroll_pos < 0) scroll_pos = 0;
        }
        
        // Home/End
        if (key == 'g') scroll_pos = 0;
        if (key == 'G') {
            scroll_pos = total_lines - display_lines;
            if (scroll_pos < 0) scroll_pos = 0;
        }
    }

    // Free all allocated memory
    for (int j = 0; j < line_count; j++) {
        free(lines[j]);
    }
    free(lines);
}

void browse(const char *path) {
    // ALLOCATE ON HEAP, NOT STACK!
    FileEntry *files = malloc(MAX_FILES * sizeof(FileEntry));
    if (!files) {
        printf("Memory allocation failed!\r\n");
        return;
    }
    
    int count, selected = 0;
    char fullpath[MAX_PATH];

    while (1) {
        list_dir(path, files, &count);
        
        if (count == 0) {
            printf("\033[2J\033[H");
            printf("Directory: %s\r\n\n", path);
            printf("(Empty directory)\r\n\n");
            printf("Press 'q' to go back\r\n");
            int key = get_key();
            if (key == 'q' || key == 'Q') {
                free(files);
                return;
            }
            continue;
        }
        
        printf("\033[2J\033[H");
        printf("Directory: %s (%d items)\r\n\n", path, count);
        
        for (int i = 0; i < count; i++) {
            if (i == selected) printf("> ");
            else printf("  ");
            printf("%s%s\r\n", files[i].name, files[i].is_dir ? "/" : "");
        }
        printf("\r\n↑↓ navigate | Enter select | q back\r\n");

        int key = get_key();
        
        if (key == 1000 && selected > 0) selected--;
        if (key == 1001 && selected < count - 1) selected++;
        if (key == 'q' || key == 'Q') {
            free(files);
            return;
        }
        
        if (key == '\r' || key == '\n' || key == 1002) {
            int len = snprintf(fullpath, MAX_PATH, "%s/%s", path, files[selected].name);
            
            if (len >= MAX_PATH) {
                printf("\033[2J\033[H");
                printf("Path too long!\r\n");
                printf("Path: %s/%s\r\n", path, files[selected].name);
                printf("Press any key to continue...\r\n");
                get_key();
                continue;
            }
            
            if (files[selected].is_dir) {
                browse(fullpath);
                selected = 0;
            } else {
                read_file(fullpath);
            }
        }
    }
}

int main(int argc, char *argv[]) {
    enable_raw_mode();
    
    char *start_path = argc > 1 ? argv[1] : ".";
    browse(start_path);
    
    printf("\033[2J\033[H");
    printf("Exiting.\r\n");
    return 0;
}
