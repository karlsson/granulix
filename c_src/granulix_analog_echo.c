#include <erl_nif.h>
#include <math.h>
#include <string.h>
#include "granulix_nif.h"

/* Code from SuperCollider plugin example:
https://github.com/supercollider/example-plugins/blob/master/03-AnalogEcho/AnalogEcho.cpp
translated to Erlang NIF library.
*/

inline float zapgremlins(float x) {
  float absx = fabsf(x);
    // very small numbers fail the first test, eliminating denormalized numbers
    //    (zero also fails the first test, but that is OK since it returns zero.)
    // very large numbers fail the second test, eliminating infinities
    // Not-a-Numbers fail both tests and are eliminated.
    return (absx > (float)1e-15 && absx < (float)1e15) ? x : (float)0.;
}

inline float cubicinterp(float x, float y0, float y1, float y2, float y3) {
    // 4-point, 3rd-order Hermite (x-form)
    float c0 = y1;
    float c1 = 0.5f * (y2 - y0);
    float c2 = y0 - 2.5f * y1 + 2.f * y2 - 0.5f * y3;
    float c3 = 0.5f * (y3 - y0) + 1.5f * (y1 - y2);

    return ((c3 * x + c2) * x + c1) * x + c0;
}

static ErlNifResourceType* analog_echo_type;

typedef struct
{
  unsigned int rate;
  FRAME_TYPE maxdelay;  // Max delay in seconds
  int bufsize;     // Size of buffer in samples, always modulo 8
  FRAME_TYPE* buf; // Buffer itself
  int writephase;  // Position of write head
  FRAME_TYPE s1;   // State of the one-pole lowpass filter
} AnalogEcho;


static ERL_NIF_TERM analog_echo_ctor(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  double maxdelay;
  unsigned int rate;
  if (!enif_get_uint(env, argv[0], &rate)){
    return enif_make_badarg(env);
  }
  if (!enif_get_double(env, argv[1], &maxdelay)){
    return enif_make_badarg(env);
  }

  AnalogEcho * aep  = enif_alloc_resource(analog_echo_type, sizeof(AnalogEcho));
  aep->rate = rate;
  aep->maxdelay = (FRAME_TYPE) maxdelay;
  aep->bufsize = ((int)(rate * aep->maxdelay) / 8 + 2) * 8;
  aep->buf = (FRAME_TYPE *) enif_alloc(aep->bufsize * FRAME_SIZE);
  memset(aep->buf, 0, aep->bufsize * FRAME_SIZE);
  aep->writephase = 0;
  aep->s1 = 0.0;
  ERL_NIF_TERM term = enif_make_resource(env, aep);
  enif_release_resource(aep);
  return term;
}

// ErlNifResourceDtor
static void ae_resource_dtor(ErlNifEnv* env, void * obj){
  enif_free(((AnalogEcho*) obj)->buf);
}

static ERL_NIF_TERM analog_echo_next(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  AnalogEcho * aep; // state pointer

  // Audio rate input output
  ErlNifBinary in_bin;
  FRAME_TYPE * out, * in;
  ERL_NIF_TERM out_term;

  // control(-rate) parameters
  double delay; // delay
  double fb;    // feedback coefficient
  double coeff; // filter coefficient

  if (!enif_get_resource(env, argv[0], analog_echo_type, (void**) &aep)){
    return enif_make_badarg(env);
  }
  if(!enif_inspect_binary(env, argv[1], &in_bin)){
    return enif_make_badarg(env);
  }

  if(!(enif_get_double(env, argv[2], &delay) &&
       enif_get_double(env, argv[3], &fb) &&
       enif_get_double(env, argv[4], &coeff))) {
    return enif_make_badarg(env);
  }

  int inNumSamples = in_bin.size / FRAME_SIZE;
  in = (FRAME_TYPE * ) in_bin.data;
  out = (FRAME_TYPE *) enif_make_new_binary(env, in_bin.size, &out_term);

  FRAME_TYPE* buf = aep->buf;
  int writephase = aep->writephase;
  FRAME_TYPE s1 = aep->s1;
  int bufsize = aep->bufsize;

  if (delay > aep->maxdelay){
    delay = aep->maxdelay;
  }

  FRAME_TYPE delay_samples = (FRAME_TYPE) aep->rate * delay;
  int offset = delay_samples;
  FRAME_TYPE frac = delay_samples - offset;

  FRAME_TYPE a = 1 - fabsf(coeff);
  for (int i = 0; i < inNumSamples; i++) {

    // Four integer phases into the buffer
    int phase1 = writephase - offset;
    int phase2 = phase1 - 1;
    int phase3 = phase1 - 2;
    int phase0 = phase1 + 1;
    FRAME_TYPE d0 = buf[advance_int_phase(phase0, bufsize)];
    FRAME_TYPE d1 = buf[advance_int_phase(phase1, bufsize)];
    FRAME_TYPE d2 = buf[advance_int_phase(phase2, bufsize)];
    FRAME_TYPE d3 = buf[advance_int_phase(phase3, bufsize)];
    // Use cubic interpolation with the fractional part of the delay in samples
    FRAME_TYPE delayed = cubicinterp(frac, d0, d1, d2, d3);

    // Apply lowpass filter and store the state of the filter.
    FRAME_TYPE lowpassed = a * delayed + coeff * s1;
    s1 = lowpassed;

    // Multiply by feedback coefficient and add to input signal.
    // zapgremlins gets rid of Bad Things like denormals, explosions, etc.
    out[i] = zapgremlins(in[i] + fb * lowpassed);
    buf[writephase] = out[i];

    writephase = advance_int_phase(writephase + 1, bufsize);
  }

  // Two variables were updated and need to be stored back into the state of the UGen.
  aep->writephase = writephase;
  aep->s1 = s1;

  return out_term;
}

/* ----------------------------------------------------------------------- */

static ErlNifFunc nif_funcs[] = {
  {"analog_echo_ctor", 2, analog_echo_ctor},
  {"analog_echo_next", 5, analog_echo_next}
};

static int open_analog_echo_resource_type(ErlNifEnv* env)
{
  const char* mod = "Elixir.Granulix.Reverb.AnalogEcho";
  const char* resource_type = "analog_echo";
  int flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
  analog_echo_type =
    enif_open_resource_type(env, mod, resource_type,
                            ae_resource_dtor, flags, NULL);
  return ((analog_echo_type == NULL) ? -1:0);
}

static int load(ErlNifEnv* caller_env, void** priv_data, ERL_NIF_TERM load_info)
{
  return open_analog_echo_resource_type(caller_env);
}

static int upgrade(ErlNifEnv* caller_env, void** priv_data, void** old_priv_data,
		   ERL_NIF_TERM load_info)
{
  return open_analog_echo_resource_type(caller_env);
}


ERL_NIF_INIT(Elixir.Granulix.Reverb.AnalogEcho, nif_funcs, load, NULL, upgrade, NULL);
