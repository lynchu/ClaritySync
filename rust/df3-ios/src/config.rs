use crate::error::{Df3Error, Result};
use configparser::ini::Ini;
use std::path::Path;

#[derive(Clone, Debug)]
pub struct Df3Config {
    pub sr: i32,
    pub fft_size: usize,
    pub hop_size: usize,
    pub nb_erb: usize,
    pub nb_df: usize,
    pub df_order: usize,
    pub df_lookahead: usize,
}

impl Df3Config {
    pub fn load(model_dir: &Path) -> Result<Self> {
        let cfg_path = model_dir.join("config.ini");
        if !cfg_path.exists() {
            return Err(Df3Error::ModelLoad("config.ini not found".into()));
        }

        let mut ini = Ini::new();
        ini.load(cfg_path.to_str().unwrap())
            .map_err(|e| Df3Error::ModelLoad(format!("read config.ini failed: {e}")))?;

        // helper
        let get_i32 = |sec: &str, key: &str, default: i32| -> i32 {
            ini.get(sec, key)
                .and_then(|v| v.trim().parse::<i32>().ok())
                .unwrap_or(default)
        };
        let get_usize = |sec: &str, key: &str, default: usize| -> usize {
            ini.get(sec, key)
                .and_then(|v| v.trim().parse::<usize>().ok())
                .unwrap_or(default)
        };

        let sr = get_i32("df", "sr", 48_000);
        let fft_size = get_usize("df", "fft_size", 960);
        let hop_size = get_usize("df", "hop_size", 480);
        let nb_erb = get_usize("df", "nb_erb", 32);
        let nb_df = get_usize("df", "nb_df", 96);
        let df_order = get_usize("df", "df_order", 5);
        let df_lookahead = get_usize("df", "df_lookahead", 2);

        Ok(Self { sr, fft_size, hop_size, nb_erb, nb_df, df_order, df_lookahead })
    }
}
