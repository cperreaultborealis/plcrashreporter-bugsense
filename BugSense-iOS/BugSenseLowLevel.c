/*
 
 BugSenseLowLevel.c
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

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <asl.h>
#include "BugSenseLowLevel.h"

#define LOG_LINE_MSG_LEN	256
#define LOG_LINE_SENDER_LEN	64
#define LOG_LINE_TIMESTAMP_LEN	64

#define IS_DEC_NUM(a)	((a)>='0'&&(a)<='9')
#define IS_OCT_NUM(a)	((a)>='0'&&(a)<='7')
#define IS_HEX_NUM(a)	\
(((a)>='0'&&(a)<='9')||((a)>='a'&&(a)<='f')||((a)>='A'&&(a)<='F'))

#ifndef EPOCH_YR
#define YEAR0			1900
#define EPOCH_YR		1970
#define SECS_DAY		(24L*60L*60L)
#define LEAPYEAR(year)		(!((year)%4)&&(((year)%100)||!((year)%400)))
#define YEARSIZE(year)		(LEAPYEAR(year)?366:365)
#endif /* EPOCH_YR */

static const int ytab[2][12] = {
	{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31},
	{31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
};

static const char levelnames[8][32] = {
	"Emergency", "Alert", "Critical", "Error", "Warning", "Notice",
	"Info", "Debug"
};

struct log_line_t {
	int level;
	int pid;
	char timestamp[LOG_LINE_TIMESTAMP_LEN];
	char sender[LOG_LINE_SENDER_LEN];
	char msg[LOG_LINE_MSG_LEN];
};

static int			atoi_async_helper(const char c,
                                      const int base,
                                      int *p, int *number);
static long long		atoll_async_helper(const char c,
                                           const int base,
                                           long long *p, long long *number);
static unsigned long long	atollu_async_helper(const char c,
                                                const int base,
                                                unsigned long long *p, unsigned long long *number);
static unsigned int 		atou_async_helper(const char c,
                                              const int base,
                                              unsigned int *p, unsigned int *number);
static void			get_base_from_str(const char *s,
                                      size_t *strt, int *base);

void *
memset_async(void *b, int c, size_t len)
{
	char *s;
	size_t i;
    
	if (!b)
		return NULL;
    
	s = (char *) b;
    
	for (i = 0; i < len; i++)
		*s++ = c;
    
	return b;
}

void
memcpy_async(void *dst, const void *src, size_t n)
{
	char *s;
	char *d;
	size_t i;
    
	if (!dst || !src)
		return;
    
	s = (char *) src;
	d = (char *) dst;
    
	for (i = 0; i < n; i++)
		*d++ = *s++;
}

int
memcmp_async(const void *s1, const void *s2, size_t n)
{
	unsigned char *ss1;
	unsigned char *ss2;
	size_t i;
    
	if (!s1 && !s2)
		return 0;
	else if (!s1)
		return -1;
	else if (!s2)
		return 1;
    
	ss1 = (unsigned char *) s1;
	ss2 = (unsigned char *) s2;
    
	for (i = 0; i < n; i++)
		if (ss1[i] != ss2[i])
			return ss1[i] - ss2[i];
    
	return 0;
}

size_t
strlen_async(const char *str)
{
	size_t i;
    
	if (!str)
		return 0;
    
	i = 0;
	while (str[i])
		i++;
    
	return i;
}

char *
strcpy_async(char *s1, const char *s2)
{
	size_t i;
    
	if (!s1)
		return NULL;
	if (!s2) {
		s1[0] = '\0';
        
		return NULL;
	}
    
	i = 0;
	while (s2[i]) {
		s1[i] = s2[i];
		i++;
	}
	s1[i] = '\0';
    
	return s1;
}

char *
strcat_async(char *s1, const char *s2)
{
	size_t l1;
    
	if (!s1)
		return NULL;
	if (!s2)
		return s1;
    
	l1 = strlen_async(s1);
	strcpy_async(&s1[l1], s2);
    
	return s1;
}

int
strcmp_async(const char *s1, const char *s2)
{
	unsigned char *ss1;
	unsigned char *ss2;
	size_t i;
    
	if (!s1 && !s2)
		return 0;
	else if (!s1)
		return -1;
	else if (!s2)
		return 1;
    
	ss1 = (unsigned char *) s1;
	ss2 = (unsigned char *) s2;
    
	i = 0;
	while (ss1[i] && ss2[i]) {
		if (ss1[i] < ss2[i])
			return -1;
		else if (ss1[i] > ss2[i])
			return 1;
		i++;
	}
	if (!ss1[i] && ss2[i])
		return -1;
	else if (ss1[i] && !ss2[i])
		return 1;
    
	return 0;
}

static void
get_base_from_str(const char *s, size_t *strt, int *base)
{
	*base = 10;
	if (s[*strt])
		if (s[*strt] == '0')
			if (s[*strt + 1]) {
				if (s[*strt + 1] == 'x' || s[*strt + 1] == 'X') {
					if (s[*strt + 2]) {
						*base = 16;
						(*strt) += 2;
					}
				} else {
					*base = 8;
					(*strt) += 1;
				}
			}
}

static int
atoi_async_helper(const char c, const int base,
                  int *p, int *number)
{
	int dig;
    
	if (10 == base) {
		if (IS_DEC_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (16 == base) {
		if (IS_HEX_NUM(c)) {
			dig = c - '0';
			if (c >= 'a' && c <= 'f')
				dig = 10 + c - 'a';
			else if (c >= 'A' && c <= 'F')
				dig = 10 + c - 'A';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (8 == base) {
		if (IS_OCT_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	}
    
	return *number;
}

int
atoi_async(const char *str)
{
	int base;
	int res, p;
	size_t i, l, strt;
    
	if (!str)
		return 0;
    
	strt = 0;
	if ('-' == str[0])
		strt = 1;
	get_base_from_str(str, &strt, &base);
	l = strlen_async(str);
	p = 1;
	res = 0;
	for (i = l - 1; i > strt; i--)
		atoi_async_helper(str[i], base, &p, &res);
	if (i == strt)
		atoi_async_helper(str[i], base, &p, &res);
    
	if ('-' == str[0])
		return -res;
    
	return res;
}

static unsigned int
atou_async_helper(const char c, const int base,
                  unsigned int *p, unsigned int *number)
{
	unsigned int dig;
    
	if (10 == base) {
		if (IS_DEC_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (16 == base) {
		if (IS_HEX_NUM(c)) {
			dig = c - '0';
			if (c >= 'a' && c <= 'f')
				dig = 10 + c - 'a';
			else if (c >= 'A' && c <= 'F')
				dig = 10 + c - 'A';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (8 == base) {
		if (IS_OCT_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	}
    
	return *number;
}

unsigned int
atou_async(const char *str)
{
	int base;
	unsigned int res, p;
	size_t i, l, strt;
    
	if (!str)
		return 0;
    
	strt = 0;
	get_base_from_str(str, &strt, &base);
	l = strlen_async(str);
	p = 1;
	res = 0;
	for (i = l - 1; i > strt; i--)
		atou_async_helper(str[i], base, &p, &res);
	if (i == strt)
		atou_async_helper(str[i], base, &p, &res);
    
	return res;
}

static long long
atoll_async_helper(const char c, const int base,
                   long long *p, long long *number)
{
	long long dig;
    
	if (10 == base) {
		if (IS_DEC_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (16 == base) {
		if (IS_HEX_NUM(c)) {
			dig = c - '0';
			if (c >= 'a' && c <= 'f')
				dig = 10 + c - 'a';
			else if (c >= 'A' && c <= 'F')
				dig = 10 + c - 'A';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (8 == base) {
		if (IS_OCT_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	}
    
	return *number;
}

long long
atoll_async(const char *str)
{
	int base;
	long long res, p;
	size_t i, l, strt;
    
	if (!str)
		return 0;
    
	strt = 0;
	if ('-' == str[0])
		strt = 1;
	get_base_from_str(str, &strt, &base);
	l = strlen_async(str);
	p = 1;
	res = 0;
	for (i = l - 1; i > strt; i--)
		atoll_async_helper(str[i], base, &p, &res);
	if (i == strt)
		atoll_async_helper(str[i], base, &p, &res);
    
	if ('-' == str[0])
		return -res;
    
	return res;
}

static unsigned long long
atollu_async_helper(const char c, const int base,
                    unsigned long long *p, unsigned long long *number)
{
	unsigned long long dig;
    
	if (10 == base) {
		if (IS_DEC_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (16 == base) {
		if (IS_HEX_NUM(c)) {
			dig = c - '0';
			if (c >= 'a' && c <= 'f')
				dig = 10 + c - 'a';
			else if (c >= 'A' && c <= 'F')
				dig = 10 + c - 'A';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	} else if (8 == base) {
		if (IS_OCT_NUM(c)) {
			dig = c - '0';
			(*number) += dig * (*p);
			(*p) *= base;
		}
	}
    
	return *number;
}

unsigned long long
atollu_async(const char *str)
{
	int base;
	unsigned long long res, p;
	size_t i, l, strt;
    
	if (!str)
		return 0;
    
	strt = 0;
	get_base_from_str(str, &strt, &base);
	l = strlen_async(str);
	p = 1;
	res = 0;
	for (i = l - 1; i > strt; i--)
		atollu_async_helper(str[i], base, &p, &res);
	if (i == strt)
		atollu_async_helper(str[i], base, &p, &res);
    
	return res;
}

char *
itoa_async(int n, char *str)
{
	int strt, i, j, x;
	char c, tmp[256];
    
	if (!str)
		return NULL;
    
	if (!n) {
		str[0] = '0';
		str[1] = '\0';
        
		return str;
	}
    
	strt = 0;
	if (n < 0) {
		str[0] = '-';
		n = -n;
		strt = 1;
	}
    
	x = 0;
	while (n) {
		c = (char) (n % 10);
		n /= 10;
		tmp[x++] = '0' + c;
	}
	tmp[x] = '\0';
    
	for (i = x - 1, j = 0; i >= 0; i--, j++)
		str[strt + j] = tmp[i];
	str[strt + j] = '\0';
    
	return str;
}

char *
utoa_async(unsigned int n, char *str)
{
	unsigned int strt, i, j, x;
	char c, tmp[256];
    
	if (!str)
		return NULL;
    
	if (!n) {
		str[0] = '0';
		str[1] = '\0';
        
		return str;
	}
    
	strt = 0;
    
	x = 0;
	while (n) {
		c = (char) (n % 10);
		n /= 10;
		tmp[x++] = '0' + c;
	}
	tmp[x] = '\0';
    
	for (i = x - 1, j = 0; i > 0; i--, j++)
		str[strt + j] = tmp[i];
	str[strt + j] = tmp[0];
	j++;
	str[strt + j] = '\0';
    
	return str;
}

char *
ltoa_async(long long n, char *str)
{
	long long strt, i, j, x;
	char c, tmp[256];
    
	if (!str)
		return NULL;
    
	if (!n) {
		str[0] = '0';
		str[1] = '\0';
        
		return str;
	}
    
	strt = 0;
	if (n < 0) {
		str[0] = '-';
		n = -n;
		strt = 1;
	}
    
	x = 0;
	while (n) {
		c = (char) (n % 10);
		n /= 10;
		tmp[x++] = '0' + c;
	}
	tmp[x] = '\0';
    
	for (i = x - 1, j = 0; i >= 0; i--, j++)
		str[strt + j] = tmp[i];
	str[strt + j] = '\0';
    
	return str;
}

char *
llutoa_async(unsigned long long n, char *str)
{
	unsigned long long strt, i, j, x;
	char c, tmp[256];
    
	if (!str)
		return NULL;
    
	if (!n) {
		str[0] = '0';
		str[1] = '\0';
        
		return str;
	}
    
	strt = 0;
    
	x = 0;
	while (n) {
		c = (char) (n % 10);
		n /= 10;
		tmp[x++] = '0' + c;
	}
	tmp[x] = '\0';
    
	for (i = x - 1, j = 0; i > 0; i--, j++)
		str[strt + j] = tmp[i];
	str[strt + j] = tmp[0];
	j++;
	str[strt + j] = '\0';
    
	return str;
}

char *
ctime_async(const time_t *clk, char *buf)
{
	struct tm tmbuf;
	time_t tim;
	unsigned long dayclock, dayno;
	int year;
	char tmp[64];
    
	if (!buf)
		return NULL;
	if (!clk) {
		buf[0] = '\0';
        
		return buf;
	}
    
	tim = *clk;
	year = EPOCH_YR;
    
	dayclock = (unsigned long) tim % SECS_DAY;
	dayno = (unsigned long) tim / SECS_DAY;
    
	memset_async(&tmbuf, 0x00, sizeof(struct tm));
    
	tmbuf.tm_sec = dayclock % 60;
	tmbuf.tm_min = (dayclock % 3600) / 60;
	tmbuf.tm_hour = dayclock / 3600;
	tmbuf.tm_wday = (dayno + 4) % 7; /* Day 0 was a Thursday */
	while (dayno >= (unsigned long) YEARSIZE(year)) {
		dayno -= YEARSIZE(year);
		year++;
	}
	tmbuf.tm_year = year - YEAR0;
	tmbuf.tm_yday = dayno;
	tmbuf.tm_mon = 0;
	while (dayno >= (unsigned long) ytab[LEAPYEAR(year)][tmbuf.tm_mon]) {
		dayno -= ytab[LEAPYEAR(year)][tmbuf.tm_mon];
		tmbuf.tm_mon++;
	}
	tmbuf.tm_mday = dayno + 1;
	tmbuf.tm_isdst = 0;
	tmbuf.tm_gmtoff = 0;
	tmbuf.tm_zone = "UTC";
    
	itoa_async(tmbuf.tm_year + YEAR0, buf);
	strcat_async(buf, "-");
	itoa_async(tmbuf.tm_mon, tmp);
	if (tmbuf.tm_mon < 10)
		strcat_async(buf, "0");
	strcat_async(buf, tmp);
	strcat_async(buf, "-");
	itoa_async(tmbuf.tm_mday, tmp);
	if (tmbuf.tm_mday < 10)
		strcat_async(buf, "0");
	strcat_async(buf, tmp);
	strcat_async(buf, " ");
	itoa_async(tmbuf.tm_hour, tmp);
	if (tmbuf.tm_hour < 10)
		strcat_async(buf, "0");
	strcat_async(buf, tmp);
	strcat_async(buf, ":");
	itoa_async(tmbuf.tm_min, tmp);
	if (tmbuf.tm_min < 10)
		strcat_async(buf, "0");
	strcat_async(buf, tmp);
	strcat_async(buf, ":");
	itoa_async(tmbuf.tm_sec, tmp);
	if (tmbuf.tm_sec < 10)
		strcat_async(buf, "0");
	strcat_async(buf, tmp);
    
	return buf;
}

int
get_system_log_messages(const int level, char *sender, int limit,
                        tag_log_row *res)
{
	const char *key, *val;
	unsigned long long llu;
	int i, j, cnt, wrapped;
	size_t s;
	aslmsg q, m;
	aslresponse r;
	char str[256];
	struct log_line_t line;
	tag_log_row rows[MAX_LOG_ROWS];
    
	q = asl_new(ASL_TYPE_QUERY);
    
	if (limit > MAX_LOG_ROWS)
		limit = MAX_LOG_ROWS;
    
	itoa_async(level, str);
	asl_set_query(q, ASL_KEY_LEVEL, str,
                  ASL_QUERY_OP_LESS_EQUAL | ASL_QUERY_OP_NUMERIC);
    
	if (sender)
		if (strlen_async(sender) > 0)
			asl_set_query(q, ASL_KEY_SENDER, sender,
                          ASL_QUERY_OP_EQUAL);
    
	r = asl_search(NULL, q);
	cnt = 0;
	wrapped = 0;
	while ((m = aslresponse_next(r))) {
		memset_async(&line, 0x00, sizeof(struct log_line_t));
		line.level = -1;
		for (i = 0; (key = asl_key(m, i)); i++) {
			val = NULL;
			if (!strcmp_async(key, "Time")) {
				val = asl_get(m, key);
				if (val) {
					llu = atollu_async(val);
					ctime_async((time_t *) &llu, str);
					strcpy_async(line.timestamp, str);
				}
			} else if (!strcmp_async(key, "PID")) {
				val = asl_get(m, key);
				if (val) {
					j = atoi_async(val);
					line.pid = j;
				}
			} else if (!strcmp_async(key, "Sender")) {
				val = asl_get(m, key);
				if (val) {
					s = strlen_async(val);
					if (s > LOG_LINE_SENDER_LEN - 1)
						s = LOG_LINE_SENDER_LEN - 1;
					memcpy_async(line.sender, val, s);
					line.sender[s] = '\0';
				}
			} else if (!strcmp_async(key, "Level")) {
				val = asl_get(m, key);
				if (val) {
					j = atoi_async(val);
					line.level = j;
				}
			} else if (!strcmp_async(key, "Message")) {
				val = asl_get(m, key);
				if (val) {
					s = strlen_async(val);
					j = 0;
					if (s > LOG_LINE_MSG_LEN - 1) {
						s = LOG_LINE_MSG_LEN - 1;
						j = 1;
					}
					memcpy_async(line.msg, val, s);
					if (j) {
						line.msg[s - 3] = '.';
						line.msg[s - 2] = '.';
						line.msg[s - 1] = '.';
					}
					line.msg[s] = '\0';
				}
			}
		}
		if (-1 != line.level) {
			strcpy_async(rows[cnt], line.timestamp);
			strcat_async(rows[cnt], " ");
			strcat_async(rows[cnt], line.sender);
			strcat_async(rows[cnt], "[");
			itoa_async(line.pid, str);
			strcat_async(rows[cnt], str);
			strcat_async(rows[cnt], "] <");
			strcat_async(rows[cnt], levelnames[line.level]);
			strcat_async(rows[cnt], ">: ");
			strcat_async(rows[cnt], line.msg);
			cnt = (cnt + 1) % limit;
			if (!cnt)
				wrapped = 1;
#ifdef TEST_ME
			printf("RESP %s %s[%d] <%s>: %s\n",
			       line.timestamp, line.sender, line.pid,
			       levelnames[line.level], line.msg);
#endif /* TEST_ME */
		}
	}
#ifdef TEST_ME
	printf("\n");
#endif /* TEST_ME */
    
	aslresponse_free(r);
    
	i = cnt;
	if (wrapped) {
		strcpy_async(res[0], "...");
		for (i = cnt, j = 1; i < limit; i++, j++)
			memcpy_async(&res[j], &rows[i], sizeof(tag_log_row));
		for (i = 0; i < cnt; i++, j++)
			memcpy_async(&res[j], &rows[i], sizeof(tag_log_row));
        
		i = limit + 1;
	} else
		for (i = 0; i < cnt; i++)
			memcpy_async(&res[i], &rows[i], sizeof(tag_log_row));
    
	return i;
}

int
read_from_log_file(tag_log_row *rows, const char *fname, int *num)
{
	char *p;
	int n;
	int fd;
	int left;
	ssize_t bytesread = 0;
    
	if (!rows || !fname)
		return -1;
    
	fd = open(fname, O_RDONLY, 0644);
	if (fd < 0)
		return -1;
    
	if (sizeof(int) != read(fd, &n, sizeof(int))) {
		close(fd);
        
		return -2;
	}
    
	/* loop until all bytes are read */
	p = &rows[0][0];
	left = n * sizeof(tag_log_row);
	while (left > 0) {
		if ((bytesread = read(fd, p, left)) <= 0) {
			if (errno == EINTR) {
				/* try again */
				bytesread = 0;
			} else {
				close(fd);
                
				return -3;
			}
		}
        
		left -= bytesread;
		p += bytesread;
	}
    
	close(fd);
    
	if (num)
		*num = n;
    
	return (int) bytesread;
}

int
write_to_log_file(tag_log_row *rows, const char *fname, const int num)
{
	char *p;
	int fd;
	int left;
	ssize_t byteswritten = 0;
    
	if (!rows || !fname)
		return -1;
	if (num <= 0)
		return 0;
    
	fd = open(fname, O_WRONLY | O_TRUNC | O_CREAT, 0644);
	if (fd < 0)
		return -1;
    
	left = num;
	if (sizeof(int) != write(fd, &left, sizeof(int))) {
		close(fd);
        
		return -1;
	}
    
	/* loop until all bytes are written */
	p = &rows[0][0];
	left = num * sizeof(tag_log_row);
	while (left > 0) {
		if ((byteswritten = write(fd, p, left)) <= 0) {
			if (errno == EINTR) {
				/* try again */
				byteswritten = 0;
			} else {
				close(fd);
                
				return -1;
			}
		}
        
		left -= byteswritten;
		p += byteswritten;
	}
    
	close(fd);
    
	return (int) byteswritten;
}

int
read_llu_from_file(unsigned long long *llu, const char *fname)
{
	int fd;
	int res;
    
	if (!llu || !fname)
		return -1;
    
	fd = open(fname, O_RDONLY, 0644);
	if (fd < 0)
		return -1;
    
	res = (int) read(fd, llu, sizeof(unsigned long long));
    
	close(fd);
    
	return res;
}

int
write_llu_to_file(const unsigned long long llu, const char *fname)
{
	int fd;
	int res;
    
	if (!fname)
		return -1;
    
	fd = open(fname, O_WRONLY | O_TRUNC | O_CREAT, 0644);
	if (fd < 0)
		return -1;
    
	res = (int) write(fd, &llu, sizeof(unsigned long long));
    
	close(fd);
    
	return res;
}