use crate::error::{Df3Error, Result};
use crate::ort_sys::*;
use libc::c_char;
use std::ffi::{CStr, CString};
use std::ptr;


pub struct Ort {
    pub api: *const OrtApi,
    env: *mut OrtEnv,
}

unsafe fn status_to_err(api: *const OrtApi, st: *mut OrtStatus, ctx: &str) -> Df3Error {
    if st.is_null() {
        return Df3Error::Process(format!("{ctx}: null status"));
    }
    let msg_ptr = ((*api).GetErrorMessage.unwrap())(st);
    let msg = if msg_ptr.is_null() {
        "(null)".to_string()
    } else {
        CStr::from_ptr(msg_ptr).to_string_lossy().to_string()
    };
    ((*api).ReleaseStatus.unwrap())(st);
    Df3Error::Ort(format!("{ctx}: {msg}"))
}

impl Ort {
    pub fn new() -> Result<Self> {
        unsafe {
            let base = OrtGetApiBase();
            if base.is_null() {
                return Err(Df3Error::ModelLoad("OrtGetApiBase returned null".into()));
            }
            let get_api = (*base)
                .GetApi
                .ok_or_else(|| Df3Error::ModelLoad("OrtApiBase.GetApi is null".into()))?;

            let api = get_api(20);
            if api.is_null() {
                return Err(Df3Error::ModelLoad("GetApi returned null (ORT_API_VERSION mismatch?)".into()));
            }

            // Prefer constant if generated; fallback to 2 (WARNING) if your header uses different names.
            #[allow(unused_variables)]
            let logging_level = {
                // Many headers generate: OrtLoggingLevel_ORT_LOGGING_LEVEL_WARNING
                #[allow(non_upper_case_globals)]
                let lvl = 2;
                lvl
            };

            let mut env: *mut OrtEnv = ptr::null_mut();
            let name = CString::new("df3_ios").unwrap();

            // signature: CreateEnv(OrtLoggingLevel, const char*, OrtEnv**)
            let st = ((*api).CreateEnv.unwrap())(
                logging_level as OrtLoggingLevel,
                name.as_ptr(),
                &mut env,
            );
            if !st.is_null() {
                return Err(status_to_err(api, st, "CreateEnv"));
            }
            if env.is_null() {
                return Err(Df3Error::ModelLoad("CreateEnv returned null env".into()));
            }

            Ok(Self { api, env })
        }
    }

    pub fn create_session(&self, model_path: &str) -> Result<*mut OrtSession> {
        unsafe {
            let mut opts: *mut OrtSessionOptions = ptr::null_mut();
            let st = ((*self.api).CreateSessionOptions.unwrap())(&mut opts);
            if !st.is_null() {
                return Err(status_to_err(self.api, st, "CreateSessionOptions"));
            }

            // Optional: keep CPU usage stable on iOS
            // ((*self.api).SetIntraOpNumThreads.unwrap())(opts, 1);

            let cpath = CString::new(model_path).map_err(|_| Df3Error::InvalidArg)?;
            let mut sess: *mut OrtSession = ptr::null_mut();
            let st = ((*self.api).CreateSession.unwrap())(self.env, cpath.as_ptr(), opts, &mut sess);
            ((*self.api).ReleaseSessionOptions.unwrap())(opts);

            if !st.is_null() {
                return Err(status_to_err(self.api, st, &format!("CreateSession({model_path})")));
            }
            if sess.is_null() {
                return Err(Df3Error::ModelLoad(format!("CreateSession returned null: {model_path}")));
            }
            Ok(sess)
        }
    }

    pub fn create_f32_tensor(&self, data: &mut [f32], shape: &[i64]) -> Result<*mut OrtValue> {
        unsafe {
            let mut mem: *mut OrtMemoryInfo = ptr::null_mut();
            let st = ((*self.api).CreateCpuMemoryInfo.unwrap())(
                OrtAllocatorType_OrtArenaAllocator,
                OrtMemType_OrtMemTypeDefault,
                &mut mem,
            );
            if !st.is_null() {
                return Err(status_to_err(self.api, st, "CreateCpuMemoryInfo"));
            }

            let mut v: *mut OrtValue = ptr::null_mut();
            let byte_len = (data.len() * std::mem::size_of::<f32>()) as usize;

            let st = ((*self.api).CreateTensorWithDataAsOrtValue.unwrap())(
                mem,
                data.as_mut_ptr() as *mut _,
                byte_len,
                shape.as_ptr(),
                shape.len() as usize,
                ONNXTensorElementDataType_ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                &mut v,
            );
            ((*self.api).ReleaseMemoryInfo.unwrap())(mem);

            if !st.is_null() {
                return Err(status_to_err(self.api, st, "CreateTensorWithDataAsOrtValue"));
            }
            if v.is_null() {
                return Err(Df3Error::Process("CreateTensorWithDataAsOrtValue returned null".into()));
            }
            Ok(v)
        }
    }

    pub fn run(
        &self,
        sess: *mut OrtSession,
        input_names: &[&str],
        input_vals: &[*mut OrtValue],
        output_names: &[&str],
    ) -> Result<Vec<*mut OrtValue>> {
        unsafe {
            let mut out: Vec<*mut OrtValue> = vec![ptr::null_mut(); output_names.len()];

            let in_c: Vec<CString> = input_names.iter().map(|s| CString::new(*s).unwrap()).collect();
            let out_c: Vec<CString> = output_names.iter().map(|s| CString::new(*s).unwrap()).collect();

            let in_ptrs: Vec<*const c_char> = in_c.iter().map(|s| s.as_ptr()).collect();
            let out_ptrs: Vec<*const c_char> = out_c.iter().map(|s| s.as_ptr()).collect();

            let input_const: Vec<*const OrtValue> =
                input_vals.iter().map(|&p| p as *const OrtValue).collect();
            let st = ((*self.api).Run.unwrap())(
                sess,
                ptr::null(),
                in_ptrs.as_ptr(),
                input_const.as_ptr(),
                input_const.len(),
                out_ptrs.as_ptr(),
                out_ptrs.len(),
                out.as_mut_ptr(),
            );

            if !st.is_null() {
                return Err(status_to_err(self.api, st, "Run"));
            }
            Ok(out)
        }
    }

    pub fn tensor_shape(&self, v: *const OrtValue) -> Result<Vec<i64>> {
        unsafe {
            let mut info: *mut OrtTensorTypeAndShapeInfo = ptr::null_mut();
            let st = ((*self.api).GetTensorTypeAndShape.unwrap())(v, &mut info);
            if !st.is_null() {
                return Err(status_to_err(self.api, st, "GetTensorTypeAndShape"));
            }

            let mut n: usize = 0;
            let st = ((*self.api).GetDimensionsCount.unwrap())(info, &mut n);
            if !st.is_null() {
                ((*self.api).ReleaseTensorTypeAndShapeInfo.unwrap())(info);
                return Err(status_to_err(self.api, st, "GetDimensionsCount"));
            }

            let mut dims = vec![0i64; n];
            let st = ((*self.api).GetDimensions.unwrap())(info, dims.as_mut_ptr(), n);
            ((*self.api).ReleaseTensorTypeAndShapeInfo.unwrap())(info);
            if !st.is_null() {
                return Err(status_to_err(self.api, st, "GetDimensions"));
            }

            Ok(dims)
        }
    }
}

impl Drop for Ort {
    fn drop(&mut self) {
        unsafe {
            if !self.env.is_null() {
                ((*self.api).ReleaseEnv.unwrap())(self.env);
                self.env = ptr::null_mut();
            }
        }
    }
}

pub unsafe fn release_value(api: *const OrtApi, v: *mut OrtValue) {
    if !v.is_null() {
        ((*api).ReleaseValue.unwrap())(v);
    }
}

pub unsafe fn release_session(api: *const OrtApi, s: *mut OrtSession) {
    if !s.is_null() {
        ((*api).ReleaseSession.unwrap())(s);
    }
}
