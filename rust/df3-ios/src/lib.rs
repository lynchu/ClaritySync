mod config;
mod engine;
mod error;
mod ort_sys;
mod ort_wrap;

use engine::Df3Engine;
use error::Df3Error;

use std::ffi::CStr;
use std::os::raw::c_char;

#[repr(C)]
pub struct Handle {
    eng: Df3Engine,
}

fn err_code(e: Df3Error) -> i32 {
    match e {
        Df3Error::NullPtr => 1,
        Df3Error::InvalidArg => 2,
        Df3Error::ModelLoad(_) => 3,
        Df3Error::Ort(_) => 4,
        Df3Error::Process(_) => 5,
    }
}

#[no_mangle]
pub extern "C" fn df3_create(model_dir: *const c_char, sample_rate: i32) -> *mut Handle {
    if model_dir.is_null() {
        return std::ptr::null_mut();
    }
    let cstr = unsafe { CStr::from_ptr(model_dir) };
    let dir = match cstr.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    match Df3Engine::new(dir, sample_rate) {
        Ok(eng) => Box::into_raw(Box::new(Handle { eng })),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn df3_set_post_filter(h: *mut Handle, enabled: bool) {
    if h.is_null() { return; }
    let handle = unsafe { &mut *h };
    handle.eng.set_post_filter(enabled);
}

#[no_mangle]
pub extern "C" fn df3_reset(h: *mut Handle) {
    if h.is_null() { return; }
    let handle = unsafe { &mut *h };
    handle.eng.reset();
}

#[no_mangle]
pub extern "C" fn df3_process(
    h: *mut Handle,
    in_ptr: *const f32,
    out_ptr: *mut f32,
    hop_size: i32,
) -> i32 {
    if h.is_null() || in_ptr.is_null() || out_ptr.is_null() {
        return err_code(Df3Error::NullPtr);
    }
    if hop_size != 480 {
        // keep streaming contract strict
        return err_code(Df3Error::InvalidArg);
    }

    let n = hop_size as usize;
    let input = unsafe { std::slice::from_raw_parts(in_ptr, n) };
    let output = unsafe { std::slice::from_raw_parts_mut(out_ptr, n) };

    let handle = unsafe { &mut *h };
    match handle.eng.process_hop(input, output) {
        Ok(_) => 0,
        Err(e) => err_code(e),
    }
}

#[no_mangle]
pub extern "C" fn df3_latency_samples(h: *mut Handle) -> i32 {
    if h.is_null() { return 0; }
    let handle = unsafe { &mut *h };
    handle.eng.latency_samples()
}

#[no_mangle]
pub extern "C" fn df3_destroy(h: *mut Handle) {
    if h.is_null() { return; }
    unsafe { drop(Box::from_raw(h)); }
}
