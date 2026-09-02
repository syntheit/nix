#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
/*
 * fajita-egl-probe — read-only surfaceless-EGL + dma-buf import diagnostic.
 *
 * Tests whether surfaceless EGL + dma-buf EGLImage import + GLES2 sample/readback
 * works on the Adreno 630 (OnePlus 6T, freedreno/turnip). This is exactly what
 * libcamera 0.7.0's DebayerEGL needs. It opens NO camera, uses NO v4l2/media-ctl/
 * libcamera, and allocates its OWN buffer. Purely diagnostic; verbose stdout.
 *
 * Tier 1 mirrors libcamera egl.cpp initEGLContext exactly.
 * Tier 2 mirrors libcamera egl.cpp createDMABufTexture2D (OUTPUT path) exactly.
 */

#define EGL_EGLEXT_PROTOTYPES
#define EGL_NO_X11
#define GL_GLEXT_PROTOTYPES

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <gbm.h>
#include <libdrm/drm_fourcc.h>
#include <linux/dma-heap.h>
#include <linux/dma-buf.h>

/* ------------------------------------------------------------------ */
/* Error-string helpers                                               */
/* ------------------------------------------------------------------ */

static const char *egl_err_str(EGLint e)
{
	switch (e) {
	case EGL_SUCCESS:             return "EGL_SUCCESS";
	case EGL_NOT_INITIALIZED:     return "EGL_NOT_INITIALIZED";
	case EGL_BAD_ACCESS:          return "EGL_BAD_ACCESS";
	case EGL_BAD_ALLOC:           return "EGL_BAD_ALLOC";
	case EGL_BAD_ATTRIBUTE:       return "EGL_BAD_ATTRIBUTE";
	case EGL_BAD_CONFIG:          return "EGL_BAD_CONFIG";
	case EGL_BAD_CONTEXT:         return "EGL_BAD_CONTEXT";
	case EGL_BAD_CURRENT_SURFACE: return "EGL_BAD_CURRENT_SURFACE";
	case EGL_BAD_DISPLAY:         return "EGL_BAD_DISPLAY";
	case EGL_BAD_MATCH:           return "EGL_BAD_MATCH";
	case EGL_BAD_NATIVE_PIXMAP:   return "EGL_BAD_NATIVE_PIXMAP";
	case EGL_BAD_NATIVE_WINDOW:   return "EGL_BAD_NATIVE_WINDOW";
	case EGL_BAD_PARAMETER:       return "EGL_BAD_PARAMETER";
	case EGL_BAD_SURFACE:         return "EGL_BAD_SURFACE";
	case EGL_CONTEXT_LOST:        return "EGL_CONTEXT_LOST";
	default:                      return "EGL_UNKNOWN";
	}
}

static const char *gl_err_str(GLenum e)
{
	switch (e) {
	case GL_NO_ERROR:                      return "GL_NO_ERROR";
	case GL_INVALID_ENUM:                  return "GL_INVALID_ENUM";
	case GL_INVALID_VALUE:                 return "GL_INVALID_VALUE";
	case GL_INVALID_OPERATION:             return "GL_INVALID_OPERATION";
	case GL_INVALID_FRAMEBUFFER_OPERATION: return "GL_INVALID_FRAMEBUFFER_OPERATION";
	case GL_OUT_OF_MEMORY:                 return "GL_OUT_OF_MEMORY";
	default:                               return "GL_UNKNOWN";
	}
}

/* Print the current EGL error as name + hex. Returns the raw code. */
static EGLint print_egl_err(const char *call)
{
	EGLint e = eglGetError();
	fprintf(stderr, "  [egl] %s failed: %s (0x%04x)\n",
	        call, egl_err_str(e), (unsigned)e);
	return e;
}

static const char *safe_str(const char *s)
{
	return s ? s : "(null)";
}

/* Lowercase a string into dst (bounded). */
static void str_tolower(char *dst, size_t dstlen, const char *src)
{
	size_t i = 0;
	if (dstlen == 0)
		return;
	if (!src) {
		dst[0] = '\0';
		return;
	}
	for (; src[i] && i + 1 < dstlen; i++) {
		char c = src[i];
		if (c >= 'A' && c <= 'Z')
			c = (char)(c - 'A' + 'a');
		dst[i] = c;
	}
	dst[i] = '\0';
}

static int str_contains(const char *hay, const char *needle)
{
	if (!hay || !needle)
		return 0;
	return strstr(hay, needle) != NULL;
}

/* ------------------------------------------------------------------ */
/* Shader helper                                                      */
/* ------------------------------------------------------------------ */

/* Compile a shader; on failure print the info log. Returns 0 on error. */
static GLuint compile_shader(GLenum type, const char *src, const char *label)
{
	GLuint sh = glCreateShader(type);
	if (!sh) {
		fprintf(stderr, "  [gl]  glCreateShader(%s) returned 0\n", label);
		return 0;
	}
	glShaderSource(sh, 1, &src, NULL);
	glCompileShader(sh);

	GLint ok = GL_FALSE;
	glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
	if (ok != GL_TRUE) {
		char log[1024];
		GLsizei n = 0;
		glGetShaderInfoLog(sh, (GLsizei)sizeof(log), &n, log);
		fprintf(stderr, "  [gl]  %s shader compile FAILED:\n%.*s\n",
		        label, (int)n, log);
		glDeleteShader(sh);
		return 0;
	}
	return sh;
}

/* ------------------------------------------------------------------ */
/* Verdict state                                                      */
/* ------------------------------------------------------------------ */

enum tier_state {
	TIER_UNKNOWN = 0,
	TIER_PASS,
	TIER_FAIL,
};

enum renderer_state {
	REND_UNKNOWN = 0,
	REND_PASS,       /* real Adreno/freedreno/turnip */
	REND_SOFTWARE,   /* llvmpipe/softpipe/swrast/... */
};

int main(void)
{
	printf("fajita-egl-probe: surfaceless-EGL + dma-buf import GPU debayer feasibility probe\n");
	printf("(read-only; opens no camera; allocates its own buffer)\n\n");

	enum tier_state tier1 = TIER_UNKNOWN;
	enum tier_state tier2 = TIER_UNKNOWN;
	enum renderer_state renderer = REND_UNKNOWN;

	int have_dmabuf_import = 0;
	int have_dmabuf_import_modifiers = 0;

	/* Describes the first failing call, for the verdict line. */
	char fail_call[256];
	fail_call[0] = '\0';
#define RECORD_FAIL(fmt, ...)                                          \
	do {                                                          \
		if (fail_call[0] == '\0')                            \
			snprintf(fail_call, sizeof(fail_call),       \
			         fmt, ##__VA_ARGS__);                \
	} while (0)

	const char *allocator = "none";
	const char *fmt_name = "ARGB8888";

	EGLDisplay display = EGL_NO_DISPLAY;
	EGLContext context = EGL_NO_CONTEXT;

	/* ============================================================ */
	printf("=== TIER 1 ===\n");
	printf("EGL init + renderer identity (mirrors libcamera initEGLContext)\n\n");

	/* 1. Bind the ES API. */
	if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
		EGLint e = print_egl_err("eglBindAPI(EGL_OPENGL_ES_API)");
		RECORD_FAIL("TIER1 eglBindAPI (0x%04x)", (unsigned)e);
		tier1 = TIER_FAIL;
		goto verdict;
	}
	printf("eglBindAPI(EGL_OPENGL_ES_API): OK\n");

	/* 2. Surfaceless platform display via the CORE 1.5 entry point,
	 *    passing EGL_DEFAULT_DISPLAY (NOT a render-node fd). */
	display = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA,
	                                EGL_DEFAULT_DISPLAY, NULL);
	if (display == EGL_NO_DISPLAY) {
		fprintf(stderr,
		        "  eglGetPlatformDisplay (core) returned EGL_NO_DISPLAY; "
		        "trying eglGetPlatformDisplayEXT fallback\n");
		PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplayEXT =
			(PFNEGLGETPLATFORMDISPLAYEXTPROC)
				eglGetProcAddress("eglGetPlatformDisplayEXT");
		if (getPlatformDisplayEXT) {
			display = getPlatformDisplayEXT(
				EGL_PLATFORM_SURFACELESS_MESA,
				EGL_DEFAULT_DISPLAY, NULL);
		} else {
			fprintf(stderr,
			        "  eglGetPlatformDisplayEXT unavailable\n");
		}
	}
	if (display == EGL_NO_DISPLAY) {
		print_egl_err("eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA)");
		RECORD_FAIL("TIER1 eglGetPlatformDisplay -> EGL_NO_DISPLAY");
		tier1 = TIER_FAIL;
		goto verdict;
	}
	printf("eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA): OK\n");

	/* 3. Initialize. */
	EGLint major = 0, minor = 0;
	if (eglInitialize(display, &major, &minor) != EGL_TRUE) {
		EGLint e = print_egl_err("eglInitialize");
		RECORD_FAIL("TIER1 eglInitialize (0x%04x)", (unsigned)e);
		tier1 = TIER_FAIL;
		goto verdict;
	}
	printf("EGL initialized: %d.%d\n", (int)major, (int)minor);

	/* 4. Identity/extension strings. */
	const char *egl_version    = eglQueryString(display, EGL_VERSION);
	const char *egl_vendor     = eglQueryString(display, EGL_VENDOR);
	const char *egl_apis       = eglQueryString(display, EGL_CLIENT_APIS);
	const char *egl_extensions = eglQueryString(display, EGL_EXTENSIONS);

	printf("EGL_VERSION     : %s\n", safe_str(egl_version));
	printf("EGL_VENDOR      : %s\n", safe_str(egl_vendor));
	printf("EGL_CLIENT_APIS : %s\n", safe_str(egl_apis));
	printf("EGL_EXTENSIONS  : %s\n", safe_str(egl_extensions));

	/* 5. Choose a pbuffer-capable ES2 config. */
	EGLint configAttribs[] = {
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_NONE
	};
	EGLConfig config;
	EGLint numConfigs = 0;
	if (eglChooseConfig(display, configAttribs, &config, 1, &numConfigs) != EGL_TRUE
	    || numConfigs < 1) {
		print_egl_err("eglChooseConfig");
		RECORD_FAIL("TIER1 eglChooseConfig (numConfigs=%d)", (int)numConfigs);
		tier1 = TIER_FAIL;
		goto verdict;
	}
	printf("eglChooseConfig: OK (numConfigs=%d)\n", (int)numConfigs);

	/* 6. Create an ES2 context. */
	EGLint contextAttribs[] = {
		EGL_CONTEXT_MAJOR_VERSION, 2,
		EGL_NONE
	};
	context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
	if (context == EGL_NO_CONTEXT) {
		print_egl_err("eglCreateContext");
		RECORD_FAIL("TIER1 eglCreateContext -> EGL_NO_CONTEXT");
		tier1 = TIER_FAIL;
		goto verdict;
	}
	printf("eglCreateContext: OK\n");

	/* 7. Make current with NO surface — truly surfaceless. */
	if (eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context) != EGL_TRUE) {
		EGLint e = print_egl_err("eglMakeCurrent(surfaceless)");
		RECORD_FAIL("TIER1 eglMakeCurrent (0x%04x)", (unsigned)e);
		tier1 = TIER_FAIL;
		goto verdict;
	}
	printf("eglMakeCurrent(EGL_NO_SURFACE, surfaceless): OK\n");

	/* 8. GL identity. */
	const char *gl_version  = (const char *)glGetString(GL_VERSION);
	const char *gl_renderer = (const char *)glGetString(GL_RENDERER);
	const char *gl_vendor   = (const char *)glGetString(GL_VENDOR);
	const char *gl_glsl     = (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION);

	printf("GL_VERSION                  : %s\n", safe_str(gl_version));
	printf("GL_RENDERER                 : %s\n", safe_str(gl_renderer));
	printf("GL_VENDOR                   : %s\n", safe_str(gl_vendor));
	printf("GL_SHADING_LANGUAGE_VERSION : %s\n", safe_str(gl_glsl));

	/* Tier-1 init succeeded. */
	tier1 = TIER_PASS;

	/* Renderer identity verdict (case-insensitive substring). */
	{
		char lower[512];
		str_tolower(lower, sizeof(lower), gl_renderer);

		int renderer_pass = str_contains(lower, "adreno")
		                  || str_contains(lower, "fd630")
		                  || str_contains(lower, "freedreno")
		                  || str_contains(lower, "turnip");

		int renderer_software = str_contains(lower, "llvmpipe")
		                     || str_contains(lower, "softpipe")
		                     || str_contains(lower, "swrast")
		                     || str_contains(lower, "zink")
		                     || str_contains(lower, "kms_swrast")
		                     || str_contains(lower, "lavapipe");

		if (renderer_software) {
			renderer = REND_SOFTWARE;
			printf("RENDERER IDENTITY: SOFTWARE (%s)\n", safe_str(gl_renderer));
			printf("  NOTE: software renderers (llvmpipe/softpipe/swrast/zink/\n");
			printf("        kms_swrast/lavapipe) let eglInitialize SUCCEED but run\n");
			printf("        all GL on the CPU via emulation. The debayer would be far\n");
			printf("        too slow — this defeats the purpose of a GPU debayer.\n");
		} else if (renderer_pass) {
			renderer = REND_PASS;
			printf("RENDERER IDENTITY: PASS (real GPU: %s)\n", safe_str(gl_renderer));
		} else {
			renderer = REND_UNKNOWN;
			printf("RENDERER IDENTITY: UNKNOWN (raw: %s) -> treat as WARN, not PASS\n",
			       safe_str(gl_renderer));
		}
	}

	/* dma-buf import extensions. */
	have_dmabuf_import =
		str_contains(egl_extensions, "EGL_EXT_image_dma_buf_import");
	have_dmabuf_import_modifiers =
		str_contains(egl_extensions, "EGL_EXT_image_dma_buf_import_modifiers");

	printf("EGL_EXT_image_dma_buf_import           : %s\n",
	       have_dmabuf_import ? "present" : "ABSENT");
	printf("EGL_EXT_image_dma_buf_import_modifiers : %s\n",
	       have_dmabuf_import_modifiers ? "present" : "absent");
	if (!have_dmabuf_import)
		printf("  WARNING: absence of EGL_EXT_image_dma_buf_import is a strong FAIL signal for Tier 2.\n");

	printf("\n");

	/* ============================================================ */
	printf("=== TIER 2 ===\n");
	printf("dma-buf EGLImage import + sample + readback (mirrors createDMABufTexture2D)\n\n");

	/* Buffer geometry. */
	const int W = 64, H = 64;
	const int bpp = 4;
	int stride = W * 4;       /* 256, 256-byte aligned */
	size_t len = (size_t)stride * H;
	(void)bpp;

	int dmabuf_fd = -1;
	int heap_ctl_fd = -1;
	int drmfd = -1;
	struct gbm_device *gbmdev = NULL;
	struct gbm_bo *bo = NULL;

	EGLImageKHR image = EGL_NO_IMAGE_KHR;
	GLuint tex = 0;
	GLuint fbo = 0;
	GLuint fbo_tex = 0;
	GLuint prog = 0;
	GLuint vs = 0, fs = 0;

	/* -- Allocate our own dma-buf. -- */

	/* 1. Preferred: dma-heap (faithful — same path libcamera output uses). */
	{
		int fd = open("/dev/dma_heap/system", O_RDWR | O_CLOEXEC);
		if (fd >= 0) {
			struct dma_heap_allocation_data data;
			memset(&data, 0, sizeof(data));
			data.len = len;
			data.fd_flags = O_RDWR | O_CLOEXEC;
			data.heap_flags = 0;
			if (ioctl(fd, DMA_HEAP_IOCTL_ALLOC, &data) == 0) {
				dmabuf_fd = (int)data.fd;
				heap_ctl_fd = fd;
				allocator = "dma-heap (faithful)";
				stride = 256;
				printf("ALLOCATOR: dma-heap (faithful) — /dev/dma_heap/system, stride=%d\n",
				       stride);
				/* Done with the heap-control fd; keep the dmabuf fd. */
				close(heap_ctl_fd);
				heap_ctl_fd = -1;
			} else {
				int e = errno;
				fprintf(stderr,
				        "  dma-heap ioctl(DMA_HEAP_IOCTL_ALLOC) failed: errno=%d (%s)\n",
				        e, strerror(e));
				close(fd);
			}
		} else {
			int e = errno;
			fprintf(stderr,
			        "  open(/dev/dma_heap/system) failed: errno=%d (%s)\n",
			        e, strerror(e));
		}
	}

	/* 2. Fallback: GBM (weaker proxy). */
	if (dmabuf_fd < 0) {
		drmfd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
		if (drmfd < 0) {
			int e = errno;
			fprintf(stderr,
			        "  open(/dev/dri/renderD128) failed: errno=%d (%s)\n",
			        e, strerror(e));
		} else {
			gbmdev = gbm_create_device(drmfd);
			if (!gbmdev) {
				int e = errno;
				fprintf(stderr,
				        "  gbm_create_device failed: errno=%d (%s)\n",
				        e, strerror(e));
				close(drmfd);
				drmfd = -1;
			} else {
				bo = gbm_bo_create(gbmdev, W, H,
				                   GBM_FORMAT_ARGB8888,
				                   GBM_BO_USE_RENDERING | GBM_BO_USE_LINEAR);
				if (!bo) {
					int e = errno;
					fprintf(stderr,
					        "  gbm_bo_create failed: errno=%d (%s)\n",
					        e, strerror(e));
					gbm_device_destroy(gbmdev);
					gbmdev = NULL;
					close(drmfd);
					drmfd = -1;
				} else {
					dmabuf_fd = gbm_bo_get_fd(bo);
					if (dmabuf_fd < 0) {
						int e = errno;
						fprintf(stderr,
						        "  gbm_bo_get_fd failed: errno=%d (%s)\n",
						        e, strerror(e));
					} else {
						stride = (int)gbm_bo_get_stride(bo);
						allocator = "GBM (weaker proxy)";
						printf("ALLOCATOR: GBM (weaker proxy) — /dev/dri/renderD128, stride=%d\n",
						       stride);
					}
				}
			}
		}
	}

	/* 3. Neither allocator worked. */
	if (dmabuf_fd < 0) {
		fprintf(stderr, "  could not allocate a dma-buf via dma-heap or GBM\n");
		RECORD_FAIL("TIER2 buffer allocation failed (no dma-heap, no GBM)");
		tier2 = TIER_FAIL;
		goto tier2_teardown;
	}

	/* -- Resolve the import entry points. -- */
	PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR_ =
		(PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
	PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR_ =
		(PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
	PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES_ =
		(PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
			eglGetProcAddress("glEGLImageTargetTexture2DOES");

	if (!eglCreateImageKHR_) {
		fprintf(stderr, "  missing proc: eglCreateImageKHR\n");
		RECORD_FAIL("TIER2 missing proc eglCreateImageKHR");
		tier2 = TIER_FAIL;
		goto tier2_teardown;
	}
	if (!eglDestroyImageKHR_) {
		fprintf(stderr, "  missing proc: eglDestroyImageKHR\n");
		RECORD_FAIL("TIER2 missing proc eglDestroyImageKHR");
		tier2 = TIER_FAIL;
		goto tier2_teardown;
	}
	if (!glEGLImageTargetTexture2DOES_) {
		fprintf(stderr, "  missing proc: glEGLImageTargetTexture2DOES\n");
		RECORD_FAIL("TIER2 missing proc glEGLImageTargetTexture2DOES");
		tier2 = TIER_FAIL;
		goto tier2_teardown;
	}

	/* -- Import the dma-buf as an EGLImage. -- */
	{
		EGLint image_attrs[] = {
			EGL_WIDTH, W,
			EGL_HEIGHT, H,
			EGL_LINUX_DRM_FOURCC_EXT, DRM_FORMAT_ARGB8888,
			EGL_DMA_BUF_PLANE0_FD_EXT, dmabuf_fd,
			EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0,
			EGL_DMA_BUF_PLANE0_PITCH_EXT, stride,
			EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, 0,
			EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, 0,
			EGL_NONE
		};
		image = eglCreateImageKHR_(display, EGL_NO_CONTEXT,
		                           EGL_LINUX_DMA_BUF_EXT, NULL, image_attrs);
		if (image == EGL_NO_IMAGE_KHR) {
			EGLint e = print_egl_err("eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT)");
			RECORD_FAIL("TIER2 eglCreateImageKHR (0x%04x)", (unsigned)e);
			tier2 = TIER_FAIL;
			goto tier2_teardown;
		}
		printf("eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT): OK\n");
	}

	/* -- Bind the imported image to a GL_TEXTURE_2D. -- */
	glGenTextures(1, &tex);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, tex);
	glEGLImageTargetTexture2DOES_(GL_TEXTURE_2D, (GLeglImageOES)image);
	{
		GLenum e = glGetError();
		if (e != GL_NO_ERROR) {
			fprintf(stderr, "  [gl] glEGLImageTargetTexture2DOES error: %s (0x%04x)\n",
			        gl_err_str(e), (unsigned)e);
			RECORD_FAIL("TIER2 glEGLImageTargetTexture2DOES (gl 0x%04x)", (unsigned)e);
			tier2 = TIER_FAIL;
			goto tier2_teardown;
		}
	}
	/* Match libcamera filter/wrap exactly. */
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	printf("glEGLImageTargetTexture2DOES: OK (imported ARGB8888 dma-buf -> GL_TEXTURE_2D)\n");

	/* -- Offscreen 4x4 RGBA8 FBO to render into. -- */
	glGenTextures(1, &fbo_tex);
	glBindTexture(GL_TEXTURE_2D, fbo_tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0,
	             GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
	                       GL_TEXTURE_2D, fbo_tex, 0);
	{
		GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		if (status != GL_FRAMEBUFFER_COMPLETE) {
			fprintf(stderr, "  [gl] framebuffer incomplete: status=0x%04x\n",
			        (unsigned)status);
			RECORD_FAIL("TIER2 glCheckFramebufferStatus (0x%04x)", (unsigned)status);
			tier2 = TIER_FAIL;
			goto tier2_teardown;
		}
	}
	printf("FBO (4x4 RGBA8): GL_FRAMEBUFFER_COMPLETE\n");

	/* -- Minimal GLES2 program sampling the imported texture. -- */
	{
		static const char *vs_src =
			"#version 100\n"
			"attribute vec2 a_pos;\n"
			"attribute vec2 a_uv;\n"
			"varying vec2 v_uv;\n"
			"void main(){ v_uv=a_uv; gl_Position=vec4(a_pos,0.0,1.0); }\n";
		static const char *fs_src =
			"#version 100\n"
			"precision mediump float;\n"
			"varying vec2 v_uv;\n"
			"uniform sampler2D tex;\n"
			"void main(){ gl_FragColor=texture2D(tex,v_uv); }\n";

		vs = compile_shader(GL_VERTEX_SHADER, vs_src, "vertex");
		if (!vs) {
			RECORD_FAIL("TIER2 vertex shader compile failed");
			tier2 = TIER_FAIL;
			goto tier2_teardown;
		}
		fs = compile_shader(GL_FRAGMENT_SHADER, fs_src, "fragment");
		if (!fs) {
			RECORD_FAIL("TIER2 fragment shader compile failed");
			tier2 = TIER_FAIL;
			goto tier2_teardown;
		}
		prog = glCreateProgram();
		glAttachShader(prog, vs);
		glAttachShader(prog, fs);
		glLinkProgram(prog);

		GLint linked = GL_FALSE;
		glGetProgramiv(prog, GL_LINK_STATUS, &linked);
		if (linked != GL_TRUE) {
			char log[1024];
			GLsizei n = 0;
			glGetProgramInfoLog(prog, (GLsizei)sizeof(log), &n, log);
			fprintf(stderr, "  [gl] program link FAILED:\n%.*s\n", (int)n, log);
			RECORD_FAIL("TIER2 glLinkProgram failed");
			tier2 = TIER_FAIL;
			goto tier2_teardown;
		}
		glUseProgram(prog);
		printf("shader compile + link: OK\n");

		/* Fullscreen quad via triangle strip, client-side arrays. */
		static const GLfloat positions[] = {
			-1.0f, -1.0f,
			 1.0f, -1.0f,
			-1.0f,  1.0f,
			 1.0f,  1.0f,
		};
		static const GLfloat uvs[] = {
			0.0f, 0.0f,
			1.0f, 0.0f,
			0.0f, 1.0f,
			1.0f, 1.0f,
		};

		GLint loc_pos = glGetAttribLocation(prog, "a_pos");
		GLint loc_uv  = glGetAttribLocation(prog, "a_uv");
		GLint loc_tex = glGetUniformLocation(prog, "tex");

		if (loc_pos >= 0) {
			glEnableVertexAttribArray((GLuint)loc_pos);
			glVertexAttribPointer((GLuint)loc_pos, 2, GL_FLOAT,
			                      GL_FALSE, 0, positions);
		}
		if (loc_uv >= 0) {
			glEnableVertexAttribArray((GLuint)loc_uv);
			glVertexAttribPointer((GLuint)loc_uv, 2, GL_FLOAT,
			                      GL_FALSE, 0, uvs);
		}

		/* Bind imported dma-buf texture to unit 0. */
		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, tex);
		if (loc_tex >= 0)
			glUniform1i(loc_tex, 0);

		glViewport(0, 0, 4, 4);
		glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		{
			GLenum e = glGetError();
			if (e != GL_NO_ERROR) {
				fprintf(stderr, "  [gl] glDrawArrays error: %s (0x%04x)\n",
				        gl_err_str(e), (unsigned)e);
				RECORD_FAIL("TIER2 glDrawArrays (gl 0x%04x)", (unsigned)e);
				tier2 = TIER_FAIL;
				goto tier2_teardown;
			}
		}
		printf("glDrawArrays(GL_TRIANGLE_STRIP): OK\n");

		unsigned char pixels[4 * 4 * 4];
		glReadPixels(0, 0, 4, 4, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
		{
			GLenum e = glGetError();
			if (e != GL_NO_ERROR) {
				fprintf(stderr, "  [gl] glReadPixels error: %s (0x%04x)\n",
				        gl_err_str(e), (unsigned)e);
				RECORD_FAIL("TIER2 glReadPixels (gl 0x%04x)", (unsigned)e);
				tier2 = TIER_FAIL;
				goto tier2_teardown;
			}
		}
		printf("glReadPixels(4x4 RGBA8): OK — first texel = %u,%u,%u,%u\n",
		       pixels[0], pixels[1], pixels[2], pixels[3]);
	}

	/* If we got here every step passed. */
	tier2 = TIER_PASS;

tier2_teardown:
	/* Teardown — best-effort; guard against double-close. */
	if (prog) glDeleteProgram(prog);
	if (vs) glDeleteShader(vs);
	if (fs) glDeleteShader(fs);
	if (fbo) glDeleteFramebuffers(1, &fbo);
	if (fbo_tex) glDeleteTextures(1, &fbo_tex);
	if (tex) glDeleteTextures(1, &tex);
	if (image != EGL_NO_IMAGE_KHR) {
		PFNEGLDESTROYIMAGEKHRPROC destroy =
			(PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
		if (destroy)
			destroy(display, image);
		image = EGL_NO_IMAGE_KHR;
	}
	if (bo) {
		gbm_bo_destroy(bo);
		bo = NULL;
	}
	if (dmabuf_fd >= 0) {
		close(dmabuf_fd);
		dmabuf_fd = -1;
	}
	if (gbmdev) {
		gbm_device_destroy(gbmdev);
		gbmdev = NULL;
	}
	if (drmfd >= 0) {
		close(drmfd);
		drmfd = -1;
	}

	printf("\n");

verdict:
	/* Tear down EGL context best-effort. */
	if (display != EGL_NO_DISPLAY) {
		eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		if (context != EGL_NO_CONTEXT)
			eglDestroyContext(display, context);
		eglTerminate(display);
	}

	/* ============================================================ */
	printf("========================================================\n");
	printf("=== VERDICT ===\n");
	printf("Tier 1 (EGL init)   : %s\n",
	       tier1 == TIER_PASS ? "OK" : (tier1 == TIER_FAIL ? "FAIL" : "not reached"));
	printf("Renderer identity   : %s\n",
	       renderer == REND_PASS ? "PASS (real GPU)"
	       : renderer == REND_SOFTWARE ? "SOFTWARE"
	       : "UNKNOWN/WARN");
	printf("dma-buf import ext  : %s\n", have_dmabuf_import ? "present" : "ABSENT");
	printf("Tier 2 (dma-buf)    : %s\n",
	       tier2 == TIER_PASS ? "PASS" : (tier2 == TIER_FAIL ? "FAIL" : "not reached"));
	printf("Allocator used      : %s\n", allocator);
	printf("Imported format     : %s\n", fmt_name);
	printf("--------------------------------------------------------\n");

	int rc;
	if (tier1 == TIER_PASS && renderer == REND_PASS
	    && have_dmabuf_import && tier2 == TIER_PASS) {
		printf("PROBE VERDICT: GPU-DEBAYER LIKELY WORKS\n");
		printf("Proceed to the on-device GPU camera test.\n");
		rc = 0;
	} else if (renderer == REND_SOFTWARE) {
		printf("PROBE VERDICT: SOFTWARE-FALLBACK-ONLY\n");
		printf("Surfaceless EGL resolves to a CPU software renderer; the GPU debayer\n");
		printf("would run emulated (too slow) — stick with the CPU debayer + flat-LUT fallback.\n");
		rc = 1;
	} else {
		printf("PROBE VERDICT: GPU-DEBAYER LIKELY FAILS\n");
		if (tier1 != TIER_PASS)
			printf("Cause: %s\n",
			       fail_call[0] ? fail_call : "Tier 1 EGL init did not complete");
		else if (!have_dmabuf_import)
			printf("Cause: EGL_EXT_image_dma_buf_import extension ABSENT (Tier 1)\n");
		else if (tier2 == TIER_FAIL)
			printf("Cause: %s\n",
			       fail_call[0] ? fail_call : "Tier 2 dma-buf import path failed");
		else if (renderer == REND_UNKNOWN)
			printf("Cause: renderer identity UNKNOWN (not a recognized real GPU)\n");
		else
			printf("Cause: %s\n", fail_call[0] ? fail_call : "unknown");
		printf("Do NOT switch to the GPU debayer; keep the CPU debayer + flat-LUT fallback.\n");
		rc = 1;
	}
	printf("========================================================\n");

	return rc;
}
