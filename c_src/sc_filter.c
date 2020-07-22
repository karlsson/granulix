/*
  SuperCollider real time audio synthesis system
  Copyright (c) 2002 James McCartney. All rights reserved.
  http://www.audiosynth.com

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
*/


// #include "SC_PlugIn.h"
#include <erl_nif.h>
#include <math.h>
#include <string.h>
#include "sc_plug.h"

static ErlNifResourceType* sc_filter_type;

// NaNs are not equal to any floating point number
static const float uninitializedControl = NAN;

#define PI 3.1415926535898

#define PUSH_LOOPVALS                           \
  int tmp_floops = unit->mRate->mFilterLoops;   \
  int tmp_fremain = unit->mRate->mFilterRemain; \
  unit->mRate->mFilterLoops = 0;                \
  unit->mRate->mFilterRemain = 1;

#define POP_LOOPVALS                            \
  unit->mRate->mFilterLoops = tmp_floops;       \
  unit->mRate->mFilterRemain = tmp_fremain;

// using namespace std; // for math functions

// static InterfaceTable* ft;

static double radians_per_sample(double rate) {
  return 2.0 * PI / rate;
}

////////////////////////////////////////////////////////////////////////////////////

typedef struct {
  double m_level, m_slope;
  int m_counter, first;
  unsigned int rate, period_size;
} Ramp;

static ERL_NIF_TERM ramp_ctor(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  unsigned int rate, period_size;

  if (!enif_get_uint(env, argv[0], &rate)){
    return enif_make_badarg(env);
  }
  if (!enif_get_uint(env, argv[1], &period_size)){
    return enif_make_badarg(env);
  }

  Ramp * unit = enif_alloc_resource(sc_filter_type, sizeof(Ramp));
  unit->rate = rate;
  unit->period_size = period_size;
  unit->m_counter = 1;
  unit->m_slope = 0.f;
  unit->first  = 1;
  ERL_NIF_TERM term = enif_make_resource(env, unit);
  enif_release_resource(unit);
  return term;
}

static ERL_NIF_TERM ramp_next(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  Ramp * unit;
  ErlNifBinary in_bin;
  double in_scalar;
  double period; // lagtime

  if (!enif_get_resource(env, argv[0],
                         sc_filter_type,
                         (void**) &unit)){
    return enif_make_badarg(env);
  }

  if(!enif_get_double(env, argv[2], &period)){
    return enif_make_badarg(env);
  }

  if(enif_inspect_binary(env, argv[1], &in_bin)){
    ERL_NIF_TERM out_term;
    int no_of_frames = in_bin.size / sizeof(float);
    float * in = (float * ) in_bin.data;
    float * out = (float *) enif_make_new_binary(env, in_bin.size, &out_term);
    if(unit->first) {
      unit->m_level = *in;
      unit->first = 0;
    }
    double slope = unit->m_slope;
    double level = unit->m_level;
    int counter = unit->m_counter;
    int remain = no_of_frames;
    while (remain) {
      int nsmps = sc_min(remain, counter);
      for(int i = 0; i < nsmps; i++) {
        *out++ = level;
        level += slope;
      }
      in += nsmps;
      counter -= nsmps;
      remain -= nsmps;
      if (counter <= 0) {
        counter = (int)(period * unit->rate / unit->period_size);
        counter = sc_max(1, counter);
        slope = (*in - level) / counter;
      }
    }
    unit->m_level = level;
    unit->m_slope = slope;
    unit->m_counter = counter;
    return out_term;
  }else if(enif_get_double(env, argv[1], &in_scalar)){
    if(unit->first) {
      unit->m_level = in_scalar;
      unit->first = 0;
    }
    double out = unit->m_level;
    if (--unit->m_counter <= 0) {
      int counter = (int)(period * unit->rate / unit->period_size);
      unit->m_counter = counter = sc_max(1, counter);
      unit->m_slope = (in_scalar - unit->m_level) / counter;
    }
    return(enif_make_double(env, out));
  }else{
    return enif_make_badarg(env);
  }
}

////////////////////////////////////////////////////////////////////////////////////

typedef struct {
  float m_lag;
  double m_b1, m_y1;
  uint rate, period_size;
  int first;
} Lag;

static ERL_NIF_TERM lag_ctor(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  unsigned int rate, period_size;
  if (!enif_get_uint(env, argv[0], &rate)){
    return enif_make_badarg(env);
  }
  if (!enif_get_uint(env, argv[1], &period_size)){
    return enif_make_badarg(env);
  }
  Lag * unit = enif_alloc_resource(sc_filter_type, sizeof(Lag));
  unit->m_lag = uninitializedControl;
  unit->m_b1 = 0.f;
  unit->rate = rate;
  unit->period_size = period_size;
  unit->first = 1;
  unit->m_y1 = uninitializedControl;
  ERL_NIF_TERM term = enif_make_resource(env, unit);
  enif_release_resource(unit);
  return term;
}

static ERL_NIF_TERM lag_next(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  Lag * unit;
  ErlNifBinary in_bin;
  float * out, * in;
  int is_bin;
  double in_scalar, out_scalar;
  ERL_NIF_TERM out_term;
  double lag;
  int inNumSamples;

  if (!enif_get_resource(env, argv[0],
                         sc_filter_type,
                         (void**) &unit)){
    return enif_raise_exception(env,
                                enif_make_string(env, "No valid reference", ERL_NIF_LATIN1));
  }

  if(enif_inspect_binary(env, argv[1], &in_bin)){
    inNumSamples = in_bin.size / sizeof(float);
    in = (float * ) in_bin.data;
    out = (float *) enif_make_new_binary(env, in_bin.size, &out_term);
    is_bin = 1;
  }else if(enif_get_double(env, argv[1], &in_scalar)){
    is_bin = 0;
  }else{
    return enif_raise_exception(env,
                                enif_make_string(env, "Not a binary nor a float", ERL_NIF_LATIN1));
  }

  if(!enif_get_double(env, argv[2], &lag)){
    return enif_raise_exception(env,
                                enif_make_string(env, "Lagtime not a float", ERL_NIF_LATIN1));
  }

  if(unit->first){
    unit->m_y1 = is_bin?(*in):in_scalar;
    unit->first = 0;
  }

  double y1 = unit->m_y1;
  double b1 = unit->m_b1;
  double y0;

  if(is_bin){
    if (lag == unit->m_lag) {
      for(int i = 0; i < inNumSamples; i++) {
        y0 = *in++;
        *out++ = y1 = y0 + b1 * (y1 - y0);
      }
    } else {
      unit->m_b1 = lag == 0.f ? 0.f : exp(unit->period_size * log001 / (lag * unit->rate));
      double b1_slope = (unit->m_b1 - b1) / unit->period_size;
      unit->m_lag = lag;
      for(int i = 0; i < inNumSamples; i++){
        b1 += b1_slope;
        y0 = *in++;
        *out++ = y1 = y0 + b1 * (y1 - y0);
      }
    }
  }else{
    if (lag == unit->m_lag) {
      y0 = in_scalar;
      out_scalar = y1 = y0 + b1 * (y1 - y0);
    } else {
      unit->m_b1 = b1 = lag == 0.f ? 0.f : exp(unit->period_size * log001 / (lag * unit->rate));
      unit->m_lag = lag;
      y0 = in_scalar;
      out_scalar = y1 = y0 + b1 * (y1 - y0);
    }
    out_term = enif_make_double(env, out_scalar);
  }
  unit->m_y1 = zapgremlins(y1);
  return out_term;
}

////////////////////////////////////////////////////////////////////////////////////
typedef struct LHPF {
  double m_freq;
  double m_y1, m_y2, m_a0, m_b1, m_b2;
  double rate, period_size;
  int first;
  void (*next)(struct LHPF *, float *, float *, double, int);
  void (*next_1)(struct LHPF *, double *, double, double);
} LHPF;

void LPF_next(LHPF * unit, float * out, float * in, double freq, int inNumSamples);
void LPF_next_1(LHPF * unit, double * out, double in, double freq);
void HPF_next(LHPF * unit, float * out, float * in, double freq, int inNumSamples);
void HPF_next_1(LHPF * unit, double * out, double in, double freq);

static ERL_NIF_TERM lhpf_ctor(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  unsigned int rate, period_size;
  char type[12];
  if (!enif_get_uint(env, argv[0], &rate)){
    return enif_make_badarg(env);
  }
  if (!enif_get_uint(env, argv[1], &period_size)){
    return enif_make_badarg(env);
  }
  if (!enif_get_atom(env, argv[1], type, 12, ERL_NIF_LATIN1)){
    return enif_make_badarg(env);
  }

  LHPF * unit = enif_alloc_resource(sc_filter_type, sizeof(LHPF));
  unit->rate = (double) rate;
  unit->period_size = (double) period_size;
  unit->first = 1;
  unit->m_a0 = 0.;
  unit->m_b1 = 0.;
  unit->m_b2 = 0.;
  unit->m_y1 = 0.;
  unit->m_y2 = 0.;
  unit->m_freq = uninitializedControl;
  if (strcmp(type, "lpf") == 0) {
    unit->next = &LPF_next;
    unit->next_1 = &LPF_next_1;
  } else if (strcmp(type, "hpf") == 0) {
    unit->next = &HPF_next;
    unit->next_1 = &HPF_next_1;
  } else {
    return enif_make_badarg(env);
  }
  ERL_NIF_TERM term = enif_make_resource(env, unit);
  enif_release_resource(unit);
  return term;
}

static ERL_NIF_TERM lhpf_next(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  LHPF * unit;
  ErlNifBinary in_bin;
  double in_scalar;
  double freq;

  if (!enif_get_resource(env, argv[0],
                         sc_filter_type,
                         (void**) &unit)){
    return enif_raise_exception(env,
                                enif_make_string(env,
                                                 "No valid reference",
                                                 ERL_NIF_LATIN1));
  }

  if(!enif_get_double(env, argv[2], &freq)){
    return enif_raise_exception(env,
                                enif_make_string(env,
                                                 "Frequency not a float",
                                                 ERL_NIF_LATIN1));
  }

  if(enif_inspect_binary(env, argv[1], &in_bin)){
    ERL_NIF_TERM out_term;
    int inNumSamples = in_bin.size / sizeof(float);
    float * in = (float *) in_bin.data;
    float * out = (float *) enif_make_new_binary(env, in_bin.size, &out_term);
    double dummy;
    if(unit->first) {
      (*unit->next_1)(unit, &dummy, (double) *in, freq);
      unit->first = 0;
    }
    (*unit->next)(unit, out, in, freq, inNumSamples);
    return out_term;
  }else if(enif_get_double(env, argv[1], &in_scalar)){
    double out;
    if(unit->first) {
      (*unit->next_1)(unit, &out, in_scalar, freq);
      unit->first = 0;
    }
    (*unit->next_1)(unit, &out, in_scalar, freq);
    return(enif_make_double(env, out));
  }else{
    return enif_raise_exception(env,
                                enif_make_string(env,
                                                 "Not a binary nor a float",
                                                 ERL_NIF_LATIN1));
  }
}

void LPF_next(LHPF* unit, float * out, float * in, double freq, int inNumSamples) {
  // printf("LPF_next\n");

  double y0;
  double y1 = unit->m_y1;
  double y2 = unit->m_y2;
  double a0 = unit->m_a0;
  double b1 = unit->m_b1;
  double b2 = unit->m_b2;
  int mFilterLoops = inNumSamples / 3;
  int mFilterRemain = inNumSamples % 3;
  double mFilterSlope = (mFilterLoops == 0) ? 0. : 1. / mFilterLoops;
  if (freq != unit->m_freq) {
    double pfreq = freq * radians_per_sample(unit->rate) * 0.5;

    double C = 1. / tan(pfreq);
    double C2 = C * C;
    double sqrt2C = C * sqrt2;
    double next_a0 = 1. / (1. + sqrt2C + C2);
    double next_b1 = -2. * (1. - C2) * next_a0;
    double next_b2 = -(1. - sqrt2C + C2) * next_a0;

    // post("%g %g %g   %g %g   %g %g %g   %g %g\n", *freq, pfreq, qres, D, C, cosf, next_b1, next_b2, next_a0, y1,
    // y2);

    double a0_slope = (next_a0 - a0) * mFilterSlope;
    double b1_slope = (next_b1 - b1) * mFilterSlope;
    double b2_slope = (next_b2 - b2) * mFilterSlope;
    for (int i = 0; i < mFilterLoops; i++) {
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 + 2. * y1 + y2);

      y2 = *in++ + b1 * y0 + b2 * y1;
      *out++ = a0 * (y2 + 2. * y0 + y1);

      y1 = *in++ + b1 * y2 + b2 * y0;
      *out++ = a0 * (y1 + 2.f * y2 + y0);

      a0 += a0_slope; b1 += b1_slope; b2 += b2_slope;
    }
    for(int i = 0; i < mFilterRemain; i++){
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 + 2. * y1 + y2);
      y2 = y1;
      y1 = y0;
    }
    unit->m_freq = freq;
    unit->m_a0 = next_a0;
    unit->m_b1 = next_b1;
    unit->m_b2 = next_b2;
  } else {
    for (int i = 0; i < mFilterLoops; i++) {
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 + 2. * y1 + y2);

      y2 = *in++ + b1 * y0 + b2 * y1;
      *out++ = a0 * (y2 + 2. * y0 + y1);

      y1 = *in++ + b1 * y2 + b2 * y0;
      *out++ = a0 * (y1 + 2. * y2 + y0);
    }
    for(int i = 0; i < mFilterRemain; i++){
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 + 2. * y1 + y2);
      y2 = y1;
      y1 = y0;
    }
  }
  unit->m_y1 = zapgremlins(y1);
  unit->m_y2 = zapgremlins(y2);
}

void LPF_next_1(LHPF* unit, double * out, double in, double freq) {
  double y0;
  double y1 = unit->m_y1;
  double y2 = unit->m_y2;
  double a0 = unit->m_a0;
  double b1 = unit->m_b1;
  double b2 = unit->m_b2;

  if (freq != unit->m_freq) {
    double pfreq = freq * radians_per_sample(unit->rate / unit->period_size) * 0.5;

    double C = 1.f / tan(pfreq);
    double C2 = C * C;
    double sqrt2C = C * sqrt2;
    a0 = 1.f / (1.f + sqrt2C + C2);
    b1 = -2.f * (1.f - C2) * a0;
    b2 = -(1.f - sqrt2C + C2) * a0;

    y0 = in + b1 * y1 + b2 * y2;
    *out = a0 * (y0 + 2. * y1 + y2);
    y2 = y1;
    y1 = y0;

    unit->m_freq = freq;
    unit->m_a0 = a0;
    unit->m_b1 = b1;
    unit->m_b2 = b2;
  } else {
    y0 = in + b1 * y1 + b2 * y2;
    *out = a0 * (y0 + 2. * y1 + y2);
    y2 = y1;
    y1 = y0;
  }
  unit->m_y1 = zapgremlins(y1);
  unit->m_y2 = zapgremlins(y2);
}


void HPF_next(LHPF* unit, float * out, float * in, double freq, int inNumSamples) {
  double y0;
  double y1 = unit->m_y1;
  double y2 = unit->m_y2;
  double a0 = unit->m_a0;
  double b1 = unit->m_b1;
  double b2 = unit->m_b2;
  int mFilterLoops = inNumSamples / 3;
  int mFilterRemain = inNumSamples % 3;
  double mFilterSlope = (mFilterLoops == 0) ? 0. : 1. / mFilterLoops;

  if (freq != unit->m_freq) {
    double pfreq = freq * radians_per_sample(unit->rate) * 0.5;

    double C = tan(pfreq);
    double C2 = C * C;
    double sqrt2C = C * sqrt2;
    double next_a0 = 1. / (1. + sqrt2C + C2);
    double next_b1 = 2. * (1. - C2) * next_a0;
    double next_b2 = -(1. - sqrt2C + C2) * next_a0;

    // post("%g %g %g   %g %g   %g %g %g   %g %g\n", *freq, pfreq, qres, D, C, cosf, next_b1, next_b2, next_a0, y1,
    // y2);

    double a0_slope = (next_a0 - a0) * mFilterSlope;
    double b1_slope = (next_b1 - b1) * mFilterSlope;
    double b2_slope = (next_b2 - b2) * mFilterSlope;
    for (int i = 0; i < mFilterLoops; i++) {
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 - 2. * y1 + y2);

      y2 = *in++ + b1 * y0 + b2 * y1;
      *out++ = a0 * (y2 - 2. * y0 + y1);

      y1 = *in++ + b1 * y2 + b2 * y0;
      *out++ = a0 * (y1 - 2. * y2 + y0);

      a0 += a0_slope; b1 += b1_slope; b2 += b2_slope;
    }
    for(int i = 0; i < mFilterRemain; i++){
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 - 2. * y1 + y2);
      y2 = y1;
      y1 = y0;
    }

    unit->m_freq = freq;
    unit->m_a0 = next_a0;
    unit->m_b1 = next_b1;
    unit->m_b2 = next_b2;
  } else {
    for (int i = 0; i < mFilterLoops; i++) {
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 - 2. * y1 + y2);

      y2 = *in++ + b1 * y0 + b2 * y1;
      *out++ = a0 * (y2 - 2. * y0 + y1);

      y1 = *in++ + b1 * y2 + b2 * y0;
      *out++ = a0 * (y1 - 2. * y2 + y0);
    }
    for(int i = 0; i < mFilterRemain; i++){
      y0 = *in++ + b1 * y1 + b2 * y2;
      *out++ = a0 * (y0 - 2. * y1 + y2);
      y2 = y1; y1 = y0;
    }
  }
  unit->m_y1 = zapgremlins(y1);
  unit->m_y2 = zapgremlins(y2);
}

void HPF_next_1(LHPF* unit, double * out, double in, double freq) {
  double y1 = unit->m_y1;
  double y2 = unit->m_y2;
  double a0 = unit->m_a0;
  double b1 = unit->m_b1;
  double b2 = unit->m_b2;

  if (freq != unit->m_freq) {
    double pfreq = freq * radians_per_sample(unit->rate / unit->period_size) * 0.5;

    double C = tan(pfreq);
    double C2 = C * C;
    double sqrt2C = C * sqrt2;
    a0 = 1. / (1. + sqrt2C + C2);
    b1 = 2. * (1. - C2) * a0;
    b2 = -(1. - sqrt2C + C2) * a0;

    double y0 = in + b1 * y1 + b2 * y2;
    *out = a0 * (y0 - 2. * y1 + y2);
    y2 = y1;
    y1 = y0;

    unit->m_freq = freq;
    unit->m_a0 = a0;
    unit->m_b1 = b1;
    unit->m_b2 = b2;
  } else {
    double y0 = in + b1 * y1 + b2 * y2;
    *out = a0 * (y0 - 2. * y1 + y2);
    y2 = y1;
    y1 = y0;
  }

  unit->m_y1 = zapgremlins(y1);
  unit->m_y2 = zapgremlins(y2);
}

/* ---------------------------------------------------------- */
static ErlNifFunc nif_funcs[] = {
  {"ramp_ctor", 2, ramp_ctor},
  {"ramp_next", 3, ramp_next},
  {"lag_ctor", 2, lag_ctor},
  {"lag_next", 3, lag_next},
  {"lhpf_ctor", 2, lhpf_ctor},
  {"lhpf_next", 3, lhpf_next}
};

static int open_filter_resource_type(ErlNifEnv* env)
{
  const char* mod = "Elixir.SC.Filter";
  const char* resource_type = "sc_filter";
  int flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
  sc_filter_type =
    enif_open_resource_type(env, mod, resource_type,
                            NULL, flags, NULL);
  return ((sc_filter_type == NULL) ? -1:0);
}

static int load(ErlNifEnv* caller_env, void** priv_data, ERL_NIF_TERM load_info)
{
  return open_filter_resource_type(caller_env);
}

static int upgrade(ErlNifEnv* caller_env, void** priv_data, void** old_priv_data,
		   ERL_NIF_TERM load_info)
{
  return open_filter_resource_type(caller_env);
}


ERL_NIF_INIT(Elixir.SC.Filter, nif_funcs, load, NULL, upgrade, NULL);
