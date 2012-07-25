
#define _BSD_SOURCE 1  /* for getdtablesize */

#include "ruby.h"
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>


static VALUE misc_utils_module;

static VALUE misc_utils_open_fds(VALUE mod);
static VALUE misc_utils_cloexec(VALUE mod, VALUE fd);

static VALUE signal_hash;
static ID id_lookup;

static VALUE misc_utils_wait_for_signal(int argc, VALUE *argv, VALUE mod);

static void args_to_sigset(int argc, VALUE *argv, sigset_t *sigset);
static int signal_from_name(const char *name);


void Init_misc_utils_ext()
{
    VALUE signal_class = rb_const_get(rb_mKernel, rb_intern("Signal"));
    ID id_list = rb_intern("list");

    misc_utils_module = rb_define_module("MiscUtils");
    rb_global_variable(&misc_utils_module);

    rb_define_module_function(misc_utils_module, "open_fds", &misc_utils_open_fds, 0);
    rb_define_module_function(misc_utils_module, "cloexec", &misc_utils_cloexec, 1);

    signal_hash = rb_funcall(signal_class, id_list, 0);
    rb_global_variable(&signal_hash);
    id_lookup = rb_intern("[]");

    rb_define_module_function(misc_utils_module, "wait_for_signal", &misc_utils_wait_for_signal, -1);
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

static VALUE misc_utils_wait_for_signal(int argc, VALUE *argv, VALUE mod)
{
    sigset_t oldset, waitset;
    int sig;
    siginfo_t si;
    int err = 0;
    const char *name;

    if (rb_thread_current() != rb_thread_main()) {
        rb_raise(rb_eThreadError, "wait_for_signal must be called from the main thread");
    }

    args_to_sigset(argc, argv, &waitset);

    pthread_sigmask(SIG_SETMASK, &waitset, &oldset);
retry:
    sig = sigwaitinfo(&waitset, &si);
    if (sig == -1) {
        if (errno == EINTR) {
            goto retry;
        }
        err = errno;
    }
    pthread_sigmask(SIG_SETMASK, &oldset, NULL);

    if (sig == -1) {
        errno = err;
        rb_sys_fail("sigwait()");
    }

    name = ruby_signal_name(sig);
    if (name != NULL) {
        return rb_str_new_cstr(name);
    } else {
        return Qnil;
    }
}

static void args_to_sigset(int argc, VALUE *argv, sigset_t *sigset)
{
    int i;
    int sig;
    sigemptyset(sigset);

    for (i = 0; i < argc; ++i) {
        switch (TYPE(argv[i])) {
        case T_FIXNUM:
            sig = FIX2INT(argv[i]);
            break;
        case T_STRING:
            sig = signal_from_name(StringValueCStr(argv[i]));
            break;
        default:
            rb_raise(rb_eTypeError, "Signals must be given as names or numbers");
        }

        sigaddset(sigset, sig);
    }
}

static int signal_from_name(const char *name)
{
    VALUE name_value;
    VALUE result;

    if (strncmp("SIG", name, 3) == 0) {
        name += 3;
    }

    name_value = rb_str_new_cstr(name);
    result = rb_funcall(signal_hash, id_lookup, 1, name_value);
    if (result == Qnil) {
        rb_raise(rb_eArgError, "Invalid signal name: %s", name);
    }
    Check_Type(result, T_FIXNUM);
    return FIX2INT(result);
}
