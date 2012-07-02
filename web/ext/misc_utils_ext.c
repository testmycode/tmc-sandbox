
#define _BSD_SOURCE 1  /* for getdtablesize */

#include "ruby.h"
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static VALUE misc_utils_module;

static VALUE misc_utils_open_fds(VALUE mod);
static VALUE misc_utils_cloexec(VALUE mod, VALUE fd);

void Init_misc_utils_ext()
{
    misc_utils_module = rb_define_module("MiscUtils");
    rb_define_module_function(misc_utils_module, "open_fds", &misc_utils_open_fds, 0);
    rb_define_module_function(misc_utils_module, "cloexec", &misc_utils_open_fds, 1);
}

static VALUE misc_utils_open_fds(VALUE mod)
{
    int fd_count = getdtablesize();
    int i;
    VALUE result = rb_ary_new();
    
    for (i = 0; i < fd_count; ++i) {
        if (fcntl(i, F_GETFD) != -1) {
            rb_ary_push(result, INT2NUM(i));
        }
    }
    
    return result;
}

static VALUE misc_utils_cloexec(VALUE mod, VALUE fd)
{
    Check_Type(fd, T_FIXNUM);
    
    if (fcntl(NUM2INT(fd), F_SETFD, FD_CLOEXEC) == -1) {
        rb_sys_fail("Failed to set FD_CLOEXEC");
    }
    
    return Qnil;
}
