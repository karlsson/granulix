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

#define PI 3.1415926535898f

#define PUSH_LOOPVALS                                                                                                  \
    int tmp_floops = unit->mRate->mFilterLoops;                                                                        \
    int tmp_fremain = unit->mRate->mFilterRemain;                                                                      \
    unit->mRate->mFilterLoops = 0;                                                                                     \
    unit->mRate->mFilterRemain = 1;

#define POP_LOOPVALS                                                                                                   \
    unit->mRate->mFilterLoops = tmp_floops;                                                                            \
    unit->mRate->mFilterRemain = tmp_fremain;

// using namespace std; // for math functions

// static InterfaceTable* ft;


//////////////////////////////////////////////////////////////////////////////////////////////////

typedef struct {
  double m_level, m_slope;
  int m_counter, rate;
} Ramp;

static ERL_NIF_TERM ramp_ctor(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  unsigned int rate;
  double level;
  if (!enif_get_uint(env, argv[0], &rate)){
    return enif_make_badarg(env);
  }
  if (!enif_get_double(env, argv[1], &level)){
    return enif_make_badarg(env);
  }

  Ramp * unit = enif_alloc_resource(sc_filter_type, sizeof(Ramp));
  unit->rate = rate;
  unit->m_counter = 1;
  unit->m_level = level;
  unit->m_slope = 0.f;

  ERL_NIF_TERM term = enif_make_resource(env, unit);
  enif_release_resource(unit);
  return term;
}

static ERL_NIF_TERM ramp_next(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  Ramp * unit;
  ErlNifBinary in_bin;
  float * out, * in;
  ERL_NIF_TERM out_term;
  double period;

  if (!enif_get_resource(env, argv[0],
                         sc_filter_type,
                         (void**) &unit)){
    return enif_make_badarg(env);
  }

  if(!enif_inspect_binary(env, argv[1], &in_bin)){
    return enif_make_badarg(env);
  }

  if(!enif_get_double(env, argv[2], &period)){
    return enif_make_badarg(env);
  }

  int no_of_frames = in_bin.size / sizeof(float);
  in = (float * ) in_bin.data;
  out = (float *) enif_make_new_binary(env, in_bin.size, &out_term);

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
      counter = (int)(period * unit->rate);
      counter = sc_max(1, counter);
      slope = (*in - level) / counter;
    }
  }
  unit->m_level = level;
  unit->m_slope = slope;
  unit->m_counter = counter;
  return out_term;
}

//////////////////////////////////////////////////////////////////////////////////////////////////

typedef struct {
  float m_lag;
  double m_b1, m_y1;
  uint rate, period_size;
  int first;
} Lag;

static ERL_NIF_TERM lag_ctor(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  unsigned int rate;
  unsigned int period_size;
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
  // lag_next(unit, 1);
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
    return enif_make_badarg(env);
  }

  if(enif_inspect_binary(env, argv[1], &in_bin)){
    inNumSamples = in_bin.size / sizeof(float);
    in = (float * ) in_bin.data;
    out = (float *) enif_make_new_binary(env, in_bin.size, &out_term);
    is_bin = 1;
  }else if(enif_get_double(env, argv[1], &in_scalar)){
    is_bin = 0;
  }else{
    return enif_make_badarg(env);
  }

  if(!enif_get_double(env, argv[2], &lag)){
    return enif_make_badarg(env);
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
      double b1_slope = (unit->m_b1 - b1) / inNumSamples; // inNumSamples = period_size
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

static ErlNifFunc nif_funcs[] = {
  {"ramp_ctor", 2, ramp_ctor},
  {"ramp_next", 3, ramp_next},
  {"lag_ctor", 2, lag_ctor},
  {"lag_next", 3, lag_next}
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
