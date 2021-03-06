/*
    This file is part of darktable,
    copyright (c) 2009--2012 Ulrich Pegelow

    darktable is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    darktable is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with darktable.  If not, see <http://www.gnu.org/licenses/>.
*/

const sampler_t sampleri =  CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_NEAREST;
const sampler_t samplerf =  CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_LINEAR;

#ifndef M_PI
#define M_PI           3.14159265358979323846  // should be defined by the OpenCL compiler acc. to standard
#endif



__kernel void
graduatedndp (read_only image2d_t in, write_only image2d_t out, const int width, const int height, const float4 color,
              const float density, const float length_base, const float length_inc_x, const float length_inc_y)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));
  
  const float len = length_base + y*length_inc_y + x*length_inc_x;

  const float t = 0.693147181f * (density * clamp(0.5f+len, 0.0f, 1.0f)/8.0f);
  const float d1 = t * t * 0.5f;
  const float d2 = d1 * t * 0.333333333f;
  const float d3 = d2 * t * 0.25f;
  float dens = 1.0f + t + d1 + d2 + d3;
  dens *= dens;
  dens *= dens;
  dens *= dens;

  pixel.xyz = fmax((float4)0.0f, pixel / (color + ((float4)1.0f - color) * (float4)dens)).xyz;
      
  write_imagef (out, (int2)(x, y), pixel); 
}


__kernel void
graduatedndm (read_only image2d_t in, write_only image2d_t out, const int width, const int height, const float4 color,
              const float density, const float length_base, const float length_inc_x, const float length_inc_y)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));
  
  const float len = length_base + y*length_inc_y + x*length_inc_x;

  const float t = 0.693147181f * (-density * clamp(0.5f-len, 0.0f, 1.0f)/8.0f);
  const float d1 = t * t * 0.5f;
  const float d2 = d1 * t * 0.333333333f;
  const float d3 = d2 * t * 0.25f;
  float dens = 1.0f + t + d1 + d2 + d3;
  dens *= dens;
  dens *= dens;
  dens *= dens;

  pixel.xyz = fmax((float4)0.0f, pixel * (color + ((float4)1.0f - color) * (float4)dens)).xyz;
      
  write_imagef (out, (int2)(x, y), pixel); 
}

__kernel void
colorize (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
          const float mix, const float L, const float a, const float b)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  pixel.x = pixel.x * mix + L - 50.0f * mix;
  pixel.y = a;
  pixel.z = b;

  write_imagef (out, (int2)(x, y), pixel); 
}


float 
GAUSS(float center, float wings, float x)
{
  const float b = -1.0f + center * 2.0f;
  const float c = (wings / 10.0f) / 2.0f;
  return exp(-(x-b)*(x-b)/(c*c));
}


__kernel void
relight (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
         const float center, const float wings, const float ev)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  const float lightness = pixel.x/100.0f;
  const float value = -1.0f+(lightness*2.0f);
  float gauss = GAUSS(center, wings, value);

  if(isnan(gauss) || isinf(gauss))
    gauss = 0.0f;

  float relight = 1.0f / exp2(-ev * clamp(gauss, 0.0f, 1.0f));

  if(isnan(relight) || isinf(relight))
    relight = 1.0f;

  pixel.x = 100.0f * clamp(lightness*relight, 0.0f, 1.0f);

  write_imagef (out, (int2)(x, y), pixel); 
}


float4 RGB_2_HSL(const float4 RGB)
{
  float H, S, L;

  // assumes that each channel is scaled to [0; 1]
  float R = RGB.x;
  float G = RGB.y;
  float B = RGB.z;

  float var_Min = fmin(R, fmin(G, B));
  float var_Max = fmax(R, fmax(G, B));
  float del_Max = var_Max - var_Min;

  L = (var_Max + var_Min) / 2.0f;

  if (del_Max == 0.0f)
  {
    H = 0.0f;
    S = 0.0f;
  }
  else
  {
    if (L < 0.5f) S = del_Max / (var_Max + var_Min);
    else          S = del_Max / (2.0f - var_Max - var_Min);

    float del_R = (((var_Max - R) / 6.0f) + (del_Max / 2.0f)) / del_Max;
    float del_G = (((var_Max - G) / 6.0f) + (del_Max / 2.0f)) / del_Max;
    float del_B = (((var_Max - B) / 6.0f) + (del_Max / 2.0f)) / del_Max;

    if      (R == var_Max) H = del_B - del_G;
    else if (G == var_Max) H = (1.0f / 3.0f) + del_R - del_B;
    else if (B == var_Max) H = (2.0f / 3.0f) + del_G - del_R;

    if (H < 0.0f) H += 1.0f;
    if (H > 1.0f) H -= 1.0f;
  }

  return (float4)(H, S, L, RGB.w);
}


float Hue_2_RGB(float v1, float v2, float vH)
{
  if (vH < 0.0f) vH += 1.0f;
  if (vH > 1.0f) vH -= 1.0f;
  if ((6.0f * vH) < 1.0f) return (v1 + (v2 - v1) * 6.0f * vH);
  if ((2.0f * vH) < 1.0f) return (v2);
  if ((3.0f * vH) < 2.0f) return (v1 + (v2 - v1) * ((2.0f / 3.0f) - vH) * 6.0f);
  return (v1);
}


float4 HSL_2_RGB(const float4 HSL)
{
  float R, G, B;

  float H = HSL.x;
  float S = HSL.y;
  float L = HSL.z;

  float var_1, var_2;

  if (S == 0.0f)
  {
    R = B = G = L;
  }
  else
  {
    if (L < 0.5f) var_2 = L * (1.0f + S);
    else          var_2 = (L + S) - (S * L);

    var_1 = 2.0f * L - var_2;

    R = Hue_2_RGB(var_1, var_2, H + (1.0f / 3.0f)); 
    G = Hue_2_RGB(var_1, var_2, H);
    B = Hue_2_RGB(var_1, var_2, H - (1.0f / 3.0f));
  } 

  // returns RGB scaled to [0; 1] for each channel
  return (float4)(R, G, B, HSL.w);
}


typedef  enum _channelmixer_output_t
{
  CHANNEL_HUE=0,
  CHANNEL_SATURATION,
  CHANNEL_LIGHTNESS,
  CHANNEL_RED,
  CHANNEL_GREEN,
  CHANNEL_BLUE,
  CHANNEL_GRAY,
  CHANNEL_SIZE
} _channelmixer_output_t;


__kernel void
channelmixer (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
              const int gray_mix_mode, global const float *red, global const float *green, global const float *blue)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  float hmix = clamp(pixel.x * red[CHANNEL_HUE], 0.0f, 1.0f) + pixel.y * green[CHANNEL_HUE] + pixel.z * blue[CHANNEL_HUE];
  float smix = clamp(pixel.x * red[CHANNEL_SATURATION], 0.0f, 1.0f) + pixel.y * green[CHANNEL_SATURATION] + pixel.z * blue[CHANNEL_SATURATION];
  float lmix = clamp(pixel.x * red[CHANNEL_LIGHTNESS], 0.0f, 1.0f) + pixel.y * green[CHANNEL_LIGHTNESS] + pixel.z * blue[CHANNEL_LIGHTNESS];

  if( hmix != 0.0f || smix != 0.0f || lmix != 0.0f )
  {
    float4 hsl = RGB_2_HSL(pixel);
    hsl.x = (hmix != 0.0f ) ? hmix : hsl.x;
    hsl.y = (smix != 0.0f ) ? smix : hsl.y;
    hsl.z = (lmix != 0.0f ) ? lmix : hsl.z;
    pixel = HSL_2_RGB(hsl);
  }

  float graymix = clamp(pixel.x * red[CHANNEL_GRAY]+ pixel.y * green[CHANNEL_GRAY] + pixel.z * blue[CHANNEL_GRAY], 0.0f, 1.0f);

  float rmix = clamp(pixel.x * red[CHANNEL_RED] + pixel.y * green[CHANNEL_RED] + pixel.z * blue[CHANNEL_RED], 0.0f, 1.0f);
  float gmix = clamp(pixel.x * red[CHANNEL_GREEN] + pixel.y * green[CHANNEL_GREEN] + pixel.z * blue[CHANNEL_GREEN], 0.0f, 1.0f);
  float bmix = clamp(pixel.x * red[CHANNEL_BLUE] + pixel.y * green[CHANNEL_BLUE] + pixel.z * blue[CHANNEL_BLUE], 0.0f, 1.0f);

  pixel = gray_mix_mode ? (float4)(graymix, graymix, graymix, pixel.w) : (float4)(rmix, gmix, bmix, pixel.w);

  write_imagef (out, (int2)(x, y), pixel); 
}


__kernel void
velvia (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
        const float strength, const float bias)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  // calculate vibrance, and apply boost velvia saturation at least saturated pixels
  float pmax = fmax(pixel.x, fmax(pixel.y, pixel.z));			// max value in RGB set
  float pmin = fmin(pixel.x, fmin(pixel.y, pixel.z));			// min value in RGB set
  float plum = (pmax + pmin) / 2.0f;				        // pixel luminocity
  float psat = (plum <= 0.5f) ? (pmax-pmin)/(1e-5f + pmax+pmin) : (pmax-pmin)/(1e-5f + fmax(0.0f, 2.0f-pmax-pmin));

  float pweight = clamp(((1.0f- (1.5f*psat)) + ((1.0f+(fabs(plum-0.5f)*2.0f))*(1.0f-bias))) / (1.0f+(1.0f-bias)), 0.0f, 1.0f); // The weight of pixel
  float saturation = strength*pweight;			// So lets calculate the final affection of filter on pixel

  float4 opixel;

  opixel.x = clamp(pixel.x + saturation*(pixel.x-0.5f*(pixel.y+pixel.z)), 0.0f, 1.0f);
  opixel.y = clamp(pixel.y + saturation*(pixel.y-0.5f*(pixel.z+pixel.x)), 0.0f, 1.0f);
  opixel.z = clamp(pixel.z + saturation*(pixel.z-0.5f*(pixel.x+pixel.y)), 0.0f, 1.0f);
  opixel.w = pixel.w;

  write_imagef (out, (int2)(x, y), opixel); 
}


__kernel void
colorcontrast (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
               const float4 scale, const float4 offset)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  const float4 Labmin = (float4)(0.0f, -128.0f, -128.0f, 0.0f);
  const float4 Labmax = (float4)(100.0f, 128.0f, 128.0f, 1.0f);

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  pixel.xyz = clamp(pixel * scale + offset, Labmin, Labmax).xyz;

  write_imagef (out, (int2)(x, y), pixel); 
}


__kernel void
vibrance (read_only image2d_t in, write_only image2d_t out, const int width, const int height, const float amount)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  const float sw = sqrt(pixel.y*pixel.y + pixel.z*pixel.z)/256.0f;
  const float ls = 1.0f - amount * sw * 0.25f;
  const float ss = 1.0f + amount * sw;

  pixel.x *= ls;
  pixel.y *= ss;
  pixel.z *= ss;

  write_imagef (out, (int2)(x, y), pixel); 
}


__kernel void
vignette (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
          const float2 scale, const float2 roi_center_scaled, const float2 expt,
          const float dscale, const float fscale, const float brightness, const float saturation)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  const float2 pv = (float2)(x,y) * scale - roi_center_scaled;

  const float cplen = pow(pow(pv.x, expt.x) + pow(pv.y, expt.x), expt.y);

  float weight = 0.0f;

  if(cplen >= dscale)
  {
    weight = ((cplen - dscale) / fscale);

    weight = weight >= 1.0f ? 1.0f : (weight <= 0.0f ? 0.0f : 0.5f - cos(M_PI * weight) / 2.0f);
  }

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  if(weight > 0)
  {
    float falloff = brightness < 0.0f ? 1.0 + (weight * brightness) : weight * brightness;

    pixel.x =clamp(brightness < 0.0f ? pixel.x * falloff : pixel.x + falloff, 0.0f, 1.0f);
    pixel.y =clamp(brightness < 0.0f ? pixel.y * falloff : pixel.y + falloff, 0.0f, 1.0f);
    pixel.z =clamp(brightness < 0.0f ? pixel.z * falloff : pixel.z + falloff, 0.0f, 1.0f);

    float mv = (pixel.x + pixel.y + pixel.z) / 3.0f;
    float wss = weight * saturation;

    pixel.x = clamp(pixel.x - (mv - pixel.x)* wss, 0.0f, 1.0f);
    pixel.y = clamp(pixel.y - (mv - pixel.y)* wss, 0.0f, 1.0f);
    pixel.z = clamp(pixel.z - (mv - pixel.z)* wss, 0.0f, 1.0f);

  }

  write_imagef (out, (int2)(x, y), pixel); 
}


/* kernel for the splittoning plugin. */
kernel void
splittoning (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
            const float compress, const float balance, const float shadow_hue, const float shadow_saturation,
            const float highlight_hue, const float highlight_saturation)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  float4 hsl = RGB_2_HSL(pixel);
  
  if(hsl.z < balance - compress || hsl.z > balance + compress)
  {
    hsl.x = hsl.z < balance ? shadow_hue : highlight_hue;
    hsl.y = hsl.z < balance ? shadow_saturation : highlight_saturation;
    float ra = hsl.z < balance ? clamp(2.0f*fabs(-balance + compress + hsl.z), 0.0f, 1.0f) : 
               clamp(2.0f*fabs(-balance - compress + hsl.z), 0.0f, 1.0f);

    float4 mixrgb = HSL_2_RGB(hsl);

    pixel.xyz = clamp(pixel * (1.0f - ra) + mixrgb * ra, (float4)0.0f, (float4)1.0f).xyz;
  }

  write_imagef (out, (int2)(x, y), pixel);
}

/* kernels to get the maximum value of an image */
kernel void
pixelmax_first (read_only image2d_t in, const int width, const int height, global float *accu, local float *buffer)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);
  const int xlsz = get_local_size(0);
  const int ylsz = get_local_size(1);
  const int xlid = get_local_id(0);
  const int ylid = get_local_id(1);

  const int l = ylid * xlsz + xlid;

  buffer[l] = (x < width && y < height) ? read_imagef(in, sampleri, (int2)(x, y)).x : -INFINITY;

  barrier(CLK_LOCAL_MEM_FENCE);

  const int lsz = xlsz * ylsz;

  for(int offset = lsz / 2; offset > 0; offset = offset / 2)
  {
    if (l < offset)
    {
      float other = buffer[l + offset];
      float mine =  buffer[l];
      buffer[l] = (mine > other) ? mine : other;
    }
    barrier(CLK_LOCAL_MEM_FENCE);
  }

  const int xgid = get_group_id(0);
  const int ygid = get_group_id(1);
  const int xgsz = get_num_groups(0);
  const int ygsz = get_num_groups(1);  

  const int m = ygid * xgsz + xgid;
  accu[m] = buffer[0];
}



__kernel void 
pixelmax_second(global float* input, global float *result, const int length, local float *buffer)
{
  int x = get_global_id(0);
  float accu = -INFINITY;

  while (x < length)
  {
    float element = input[x];
    accu = (accu > element) ? accu : element;
    x += get_global_size(0);
  }
  
  int lid = get_local_id(0);
  buffer[lid] = accu;

  barrier(CLK_LOCAL_MEM_FENCE);

  for(int offset = get_local_size(0) / 2; offset > 0; offset = offset / 2)
  {
    if (lid < offset)
    {
      float other = buffer[lid + offset];
      float mine = buffer[lid];
      buffer[lid] = (mine > other) ? mine : other;
    }
    barrier(CLK_LOCAL_MEM_FENCE);
  }

  if (lid == 0)
  {
    result[get_group_id(0)] = buffer[0];
  }
}


/* kernel for the global tonemap plugin: reinhard */
kernel void
global_tonemap_reinhard (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
            const float4 parameters)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  float l = pixel.x * 0.01f;

  pixel.x = 100.0f * (l/(1.0f + l));

  write_imagef (out, (int2)(x, y), pixel);
}



/* kernel for the global tonemap plugin: drago */
kernel void
global_tonemap_drago (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
            const float4 parameters)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  const float eps = parameters.x;
  const float ldc = parameters.y; 
  const float bl = parameters.z;
  const float lwmax = parameters.w;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  float lw = pixel.x * 0.01f;

  pixel.x = 100.0f * (ldc * log(fmax(eps, lw + 1.0f)) / log(fmax(eps, 2.0f + (pow(lw/lwmax,bl)) * 8.0f)));

  write_imagef (out, (int2)(x, y), pixel);
}


/* kernel for the global tonemap plugin: filmic */
kernel void
global_tonemap_filmic (read_only image2d_t in, write_only image2d_t out, const int width, const int height,
            const float4 parameters)
{
  const int x = get_global_id(0);
  const int y = get_global_id(1);

  if(x >= width || y >= height) return;

  float4 pixel = read_imagef(in, sampleri, (int2)(x, y));

  float l = pixel.x * 0.01f;
  float m = fmax(0.0f, l - 0.004f);

  pixel.x = 100.0f * ((m*(6.2f*m+.5f))/(m*(6.2f*m+1.7f)+0.06f));

  write_imagef (out, (int2)(x, y), pixel);
}



