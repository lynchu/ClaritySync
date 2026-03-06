use crate::{
    config::Df3Config,
    error::{Df3Error, Result},
    ort_wrap::{release_session, release_value, Ort},
};
use std::path::Path;

pub struct Df3Engine {
    cfg: Df3Config,
    post_filter: bool,

    ort: Ort,
    enc: *mut crate::ort_sys::OrtSession,
    erb_dec: *mut crate::ort_sys::OrtSession,
    df_dec: *mut crate::ort_sys::OrtSession,
}

impl Df3Engine {
    pub fn new(model_dir: &str, sample_rate: i32) -> Result<Self> {
        let dir = Path::new(model_dir);
        let cfg = Df3Config::load(dir)?;

        if sample_rate != cfg.sr {
            return Err(Df3Error::InvalidArg);
        }

        for f in ["enc.onnx", "erb_dec.onnx", "df_dec.onnx", "config.ini"] {
            if !dir.join(f).exists() {
                return Err(Df3Error::ModelLoad(format!("missing file: {f}")));
            }
        }

        let ort = Ort::new()?;

        let enc = ort.create_session(&dir.join("enc.onnx").to_string_lossy())?;
        let erb_dec = ort.create_session(&dir.join("erb_dec.onnx").to_string_lossy())?;
        let df_dec = ort.create_session(&dir.join("df_dec.onnx").to_string_lossy())?;

        let mut eng = Self {
            cfg,
            post_filter: true,
            ort,
            enc,
            erb_dec,
            df_dec,
        };

        eng.debug_dummy_infer_s1()?; // validate ORT + model IO names

        Ok(eng)
    }

    fn debug_dummy_infer_s1(&mut self) -> Result<()> {
        let s: i64 = 1;

        let mut feat_erb = vec![0.0f32; 1 * 1 * 1 * 32];
        let mut feat_spec = vec![0.0f32; 1 * 2 * 1 * 96];

        let erb_v = self.ort.create_f32_tensor(&mut feat_erb, &[1, 1, s, 32])?;
        let spec_v = self.ort.create_f32_tensor(&mut feat_spec, &[1, 2, s, 96])?;

        let enc_out = self.ort.run(
            self.enc,
            &["feat_erb", "feat_spec"],
            &[erb_v, spec_v],
            &["e0", "e1", "e2", "e3", "emb", "c0", "lsnr"],
        )?;

        for (name, v) in ["e0","e1","e2","e3","emb","c0","lsnr"].iter().zip(enc_out.iter()) {
            let shp = self.ort.tensor_shape(*v)?;
            eprintln!("[DF3][ORT] enc out {name} shape = {:?}", shp);
        }

        let erb_out = self.ort.run(
            self.erb_dec,
            &["emb", "e3", "e2", "e1", "e0"],
            &[enc_out[4], enc_out[3], enc_out[2], enc_out[1], enc_out[0]],
            &["m"],
        )?;
        eprintln!("[DF3][ORT] erb_dec out m shape = {:?}", self.ort.tensor_shape(erb_out[0])?);

        let df_out = self.ort.run(
            self.df_dec,
            &["emb", "c0"],
            &[enc_out[4], enc_out[5]],
            &["coefs", "235"],
        )?;
        eprintln!("[DF3][ORT] df_dec out coefs shape = {:?}", self.ort.tensor_shape(df_out[0])?);
        eprintln!("[DF3][ORT] df_dec out 235 shape = {:?}", self.ort.tensor_shape(df_out[1])?);

        unsafe {
            let api = self.ort.api;
            release_value(api, erb_v);
            release_value(api, spec_v);
            for v in enc_out { release_value(api, v); }
            for v in erb_out { release_value(api, v); }
            for v in df_out { release_value(api, v); }
        }
        Ok(())
    }

    pub fn set_post_filter(&mut self, enabled: bool) {
        self.post_filter = enabled;
    }

    pub fn reset(&mut self) {
        // TODO: reset streaming state once DSP is implemented
    }

    pub fn process_hop(&mut self, input: &[f32], output: &mut [f32]) -> Result<()> {
        if input.len() != output.len() { return Err(Df3Error::InvalidArg); }
        if input.len() != self.cfg.hop_size { return Err(Df3Error::InvalidArg); }
        output.copy_from_slice(input); // keep stable first
        Ok(())
    }

    pub fn latency_samples(&self) -> i32 {
        (self.cfg.df_lookahead * self.cfg.hop_size) as i32
    }
}

impl Drop for Df3Engine {
    fn drop(&mut self) {
        unsafe {
            let api = self.ort.api;
            release_session(api, self.enc);
            release_session(api, self.erb_dec);
            release_session(api, self.df_dec);
        }
    }
}
