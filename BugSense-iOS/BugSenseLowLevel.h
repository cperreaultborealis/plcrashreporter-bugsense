/*
 
 BugSenseLowLevel.h
 BugSense-iOS
 
 Copyright (c) 2012 BugSense Inc.
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 
 Author: Dionysis Kakolyris, dgk@bugsense.com
 
 */

#ifndef BugSense_iOS_BugSenseLowLevel_h
#define BugSense_iOS_BugSenseLowLevel_h

#define MAX_LOG_ROWS	1000
#define LOG_ROW_LEN	512

typedef char tag_log_row[LOG_ROW_LEN];

int                 atoi_async(const char *str);
long long           atoll_async(const char *str);
unsigned long long	atollu_async(const char *str);
unsigned int		atou_async(const char *str);
char                *ctime_async(const time_t *clk, char *buf);
int                 get_system_log_messages(const int level, char *sender, int limit, tag_log_row *res);
char                *itoa_async(int n, char *str);
char                *llutoa_async(unsigned long long n, char *str);
char                *ltoa_async(long long n, char *str);
void                memcpy_async(void *dst, const void *src, size_t n);
int                 memcmp_async(const void *s1, const void *s2, size_t n);
void                *memset_async(void *b, int c, size_t len);
int                 read_from_log_file(tag_log_row *rows, const char *fname, int *num);
int                 read_llu_from_file(unsigned long long *llu, const char *fname);
char                *strcat_async(char *s1, const char *s2);
int                 strcmp_async(const char *s1, const char *s2);
char                *strcpy_async(char *s1, const char *s2);
size_t              strlen_async(const char *str);
char                *utoa_async(unsigned int n, char *str);
int                 write_llu_to_file(const unsigned long long llu, const char *fname);
int                 write_to_log_file(tag_log_row *rows, const char *fname, const int num);

#endif
