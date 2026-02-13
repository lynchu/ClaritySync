//
//  df3.h
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/13.
//

#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* DF3Handle;

// model_dir: directory containing enc.onnx / erb_dec.onnx / df_dec.onnx / config.ini
DF3Handle df3_create(const char* model_dir, int32_t sample_rate);

// default post-filter enabled; user can toggle at runtime
void df3_set_post_filter(DF3Handle h, bool enabled);

void df3_reset(DF3Handle h);

// hop-based processing, mono float32
int32_t df3_process(DF3Handle h, const float* in_ptr, float* out_ptr, int32_t hop_size);

int32_t df3_latency_samples(DF3Handle h);
void df3_destroy(DF3Handle h);

#ifdef __cplusplus
}
#endif
