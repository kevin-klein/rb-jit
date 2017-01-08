extern crate ruby_sys;
extern crate libc;

use std::ffi::{CString, CStr};
use ruby_sys::value::{RubySpecialConsts, RubySpecialFlags};
use ruby_sys::float;
use ruby_sys::types::Value;
use libc::{c_char};

pub fn rb_float_new(i: f64) -> i64 {
    let result = unsafe { float::rb_float_new(i) };
    result.value as i64
}

pub fn rb_num2dbl(i: i64) -> f64 {
    let val = Value { value: i as usize };
    unsafe { float::rb_num2dbl(val) as f64 }
}

fn fix_nums(i1: i64, i2: i64) -> bool {
    (i1 & i2 & 1) == RubySpecialFlags::FixnumFlag as i64
}

fn float_nums(i1: i64, i2: i64) -> bool {
    ((((i1)^2) | ((i2)^2)) & 3) == 0
}

fn fix2long(i: i64) -> i64 {
    i >> 1
}

fn long2num(i: i64) -> i64 {
    (i << 1) | 1
}

extern "C" {
    pub fn rb_funcallv(receiver: i64, method: i64, argc: i64, argv: *const i64) -> i64;
    pub fn rb_intern(name: *const c_char) -> i64;
    pub fn rb_str_resurrect(s: i64) -> i64;
    pub fn rb_str_new(s: *const c_char, len: i64) -> i64;
    pub fn rb_string_value_cstr(s: *const i64) -> *const c_char;
}

fn str_to_cstring(str: &str) -> CString {
    CString::new(str).unwrap()
}

pub fn cstr_as_string(str: *const c_char) -> String {
    unsafe { CStr::from_ptr(str).to_string_lossy().into_owned() }
}

fn internal_id(string: &str) -> i64 {
    let str = str_to_cstring(string);

    unsafe { rb_intern(str.as_ptr()) }
}

#[no_mangle]
pub extern fn opt_plus(lhs: i64, rhs: i64) -> i64 {
    if fix_nums(lhs, rhs) {
        long2num(fix2long(lhs) + fix2long(rhs))
    }
    else if float_nums(lhs, rhs) {
        rb_float_new(rb_num2dbl(lhs) + rb_num2dbl(rhs))
    }
    else {
        let method_id = internal_id("+");

        unsafe { rb_funcallv(lhs, method_id, 1, vec![rhs].as_ptr()) }
    }
}

#[no_mangle]
pub extern fn opt_minus(lhs: i64, rhs: i64) -> i64 {
    if fix_nums(lhs, rhs) {
        long2num(fix2long(lhs) - fix2long(rhs))
    }
    else if float_nums(lhs, rhs) {
        rb_float_new(rb_num2dbl(lhs) - rb_num2dbl(rhs))
    }
    else {
        let method_id = internal_id("-");

        unsafe { rb_funcallv(lhs, method_id, 1, vec![rhs].as_ptr()) }
    }
}

#[no_mangle]
pub extern fn opt_mult(lhs: i64, rhs: i64) -> i64 {
    if fix_nums(lhs, rhs) {
        long2num(fix2long(lhs) * fix2long(rhs))
    }
    else if float_nums(lhs, rhs) {
        rb_float_new(rb_num2dbl(lhs) * rb_num2dbl(rhs))
    }
    else {
        let method_id = internal_id("*");

        unsafe { rb_funcallv(lhs, method_id, 1, vec![rhs].as_ptr()) }
    }
}

#[no_mangle]
pub extern fn opt_div(lhs: i64, rhs: i64) -> i64 {
    if fix_nums(lhs, rhs) && rhs != 0 {
        long2num(fix2long(lhs) / fix2long(rhs))
    }
    else if float_nums(lhs, rhs) {
        rb_float_new(rb_num2dbl(lhs) / rb_num2dbl(rhs))
    }
    else {
        let method_id = internal_id("/");

        unsafe { rb_funcallv(lhs, method_id, 1, vec![rhs].as_ptr()) }
    }
}

#[no_mangle]
pub extern fn opt_gt(lhs: i64, rhs: i64) -> i64 {
    if fix_nums(lhs, rhs) {
        match lhs > rhs {
            true    => RubySpecialConsts::True as i64,
            false   => RubySpecialConsts::False as i64
        }
    }
    else if float_nums(lhs, rhs) {
        match rb_num2dbl(lhs) > rb_num2dbl(rhs) {
            true    => RubySpecialConsts::True as i64,
            false   => RubySpecialConsts::False as i64
        }
    }
    else {
        let method_id = internal_id(">");

        unsafe { rb_funcallv(lhs, method_id, 1, vec![rhs].as_ptr()) }
    }
}

#[no_mangle]
pub extern fn concat_string_literals(num: i64, args: *const i64) -> i64 {
    if num == 0 {
        let s = "".as_ptr() as *const c_char;
        return unsafe { rb_str_new(s, 0) }
    }

    let mut result = String::new();
    for i in 0..num {
        let str_object = unsafe { *args.offset(i as isize) };
        let s = unsafe { cstr_as_string(rb_string_value_cstr(&str_object)) };
        result.push_str(s.as_str());
    }

    unsafe { rb_str_new(result.as_str().as_ptr() as *const c_char, result.len() as i64) }
}
