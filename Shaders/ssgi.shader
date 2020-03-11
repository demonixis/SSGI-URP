Shader "Custom/RenderFeature/SSGI"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass // SSAO
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            sampler2D _CameraDepthTexture;

            float4 _MainTex_TexelSize;
            float4 _MainTex_ST;

            int _SamplesCount;
            float _IndirectAmount;
            float _NoiseAmount;
            int _Noise;
            float4x4 _InverseProjectionMatrix;

            float2 mod_dither3(float2 u) 
            {
                float noiseX = fmod(u.x + u.y + fmod(208. + u.x * 3.58, 13. + fmod(u.y * 22.9, 9.)), 7.) * .143;
                float noiseY = fmod(u.y + u.x + fmod(203. + u.y * 3.18, 12. + fmod(u.x * 27.4, 8.)), 6.) * .139;
                return float2(noiseX, noiseY) * 2.0 - 1.0;
            }

            float2 dither(float2 coord, float seed, float2 size) 
            {
                float noiseX = ((frac(1.0 - (coord.x + seed * 1.0) * (size.x / 2.0)) * 0.25) + (frac((coord.y + seed * 2.0) * (size.y / 2.0)) * 0.75)) * 2.0 - 1.0;
                float noiseY = ((frac(1.0 - (coord.x + seed * 3.0) * (size.x / 2.0)) * 0.75) + (frac((coord.y + seed * 4.0) * (size.y / 2.0)) * 0.25)) * 2.0 - 1.0;
                return float2(noiseX, noiseY);
            }

            float3 getViewPos(sampler2D tex, float2 coord, float4x4 ipm) 
            {
                float depth = tex2D(tex, coord).r;

                //Turn the current pixel from ndc to world coordinates
                float3 pixel_pos_ndc = float3(coord * 2.0 - 1.0, depth * 2.0 - 1.0);
                float4 pixel_pos_clip = mul(ipm, float4(pixel_pos_ndc, 1.0));
                float3 pixel_pos_cam = pixel_pos_clip.xyz / pixel_pos_clip.w;
                return pixel_pos_cam;
            }

            float3 getViewNormal(sampler2D tex, float2 coord, float4x4 ipm)
            {
                float pW = _MainTex_TexelSize.x;
                float pH = _MainTex_TexelSize.y;

                float3 p1 = getViewPos(tex, coord + float2(pW, 0.0), ipm).xyz;
                float3 p2 = getViewPos(tex, coord + float2(0.0, pH), ipm).xyz;
                float3 p3 = getViewPos(tex, coord + float2(-pW, 0.0), ipm).xyz;
                float3 p4 = getViewPos(tex, coord + float2(0.0, -pH), ipm).xyz;

                float3 vP = getViewPos(tex, coord, ipm);

                float3 dx = vP - p1;
                float3 dy = p2 - vP;
                float3 dx2 = p3 - vP;
                float3 dy2 = vP - p4;

                if (length(dx2) < length(dx) && coord.x - pW >= 0.0 || coord.x + pW > 1.0) 
                {
                    dx = dx2;
                }

                if (length(dy2) < length(dy) && coord.y - pH >= 0.0 || coord.y + pH > 1.0) 
                {
                    dy = dy2;
                }

                return normalize(-cross(dx, dy).xyz);
            }

            float lenSq(float3 v) 
            {
                return pow(v.x, 2.0) + pow(v.y, 2.0) + pow(v.z, 2.0);
            }

            float3 lightSample(sampler2D color_tex, sampler2D depth_tex, float2 coord, float4x4 ipm, float2 lightcoord, float3 normal, float3 position, float n, float2 texsize)
            {
                float2 random = float2(1.0, 1.0);

                if (_Noise > 0)
                {
                    random = (mod_dither3((coord * texsize) + float2(n * 82.294, n * 127.721))) * 0.01 * _NoiseAmount;
                }
                else 
                {
                    random = dither(coord, 1.0, texsize) * 0.1 * _NoiseAmount;
                }

                lightcoord *= float2(0.7, 0.7);

                //light absolute data
                float3 lightcolor = tex2D(color_tex, ((lightcoord)+random)).rgb;
                float3 lightnormal = getViewNormal(depth_tex, frac(lightcoord) + random, ipm).rgb;
                float3 lightposition = getViewPos(depth_tex, frac(lightcoord) + random, ipm).xyz;

                //light variable data
                float3 lightpath = lightposition - position;
                float3 lightdir = normalize(lightpath);

                //falloff calculations
                float cosemit = clamp(dot(lightdir, -lightnormal), 0.0, 1.0); //emit only in one direction
                float coscatch = clamp(dot(lightdir, normal) * 0.5 + 0.5, 0.0, 1.0); //recieve light from one direction
                float distfall = pow(lenSq(lightpath), 0.1) + 1.0;        //fall off with distance

                return (lightcolor * cosemit * coscatch / distfall) * (length(lightposition) / 20.0);
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag(v2f input) : SV_Target
            {
                float3 direct = tex2D(_MainTex, input.uv).rgb;
                float3 color = normalize(direct).rgb;
                float3 indirect = float3(0.0,0.0,0.0);
                float PI = 3.14159;
                float2 texSize = _MainTex_TexelSize.zw;
                //fragment geometry data
                float3 position = getViewPos(_CameraDepthTexture, input.uv, _InverseProjectionMatrix);
                float3 normal = getViewNormal(_CameraDepthTexture, input.uv, _InverseProjectionMatrix);

                //sampling in spiral

                float dlong = PI * (3.0 - sqrt(5.0));
                float dz = 1.0 / float(_SamplesCount);
                float l = 0.0;
                float z = 1.0 - dz / 2.0;

                for (int i = 0; i < _SamplesCount; i++)
                {

                    float r = sqrt(1.0 - z);

                    float xpoint = (cos(l) * r) * 0.5 + 0.5;
                    float ypoint = (sin(l) * r) * 0.5 + 0.5;

                    z = z - dz;
                    l = l + dlong;

                    indirect += lightSample(_MainTex, _CameraDepthTexture, input.uv, _InverseProjectionMatrix, float2(xpoint, ypoint), normal, position, float(i), texSize);

                }

                return fixed4(direct + (indirect / float(_SamplesCount) * _IndirectAmount), 1);
            }
            ENDCG
        }
    }
}
