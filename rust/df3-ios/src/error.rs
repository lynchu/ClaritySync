use thiserror::Error;

#[derive(Error, Debug)]
pub enum Df3Error {
    #[error("null pointer")]
    NullPtr,
    #[error("invalid argument")]
    InvalidArg,
    #[error("model load failed: {0}")]
    ModelLoad(String),
    #[error("process failed: {0}")]
    Process(String),
}

pub type Result<T> = std::result::Result<T, Df3Error>;
