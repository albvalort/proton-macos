/* glcapture: saves the back buffer of a native macOS OpenGL app as PPM files.
 *
 *   GLCAPTURE_DIR=/tmp/frames [GLCAPTURE_INTERVAL=60] DYLD_INSERT_LIBRARIES=glcapture.dylib app
 *
 * Used to compare a game's native rendering with the same content under Wine. */
#define GL_SILENCE_DEPRECATION
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } _interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static void capture(void)
{
    static const char *dir;
    static int interval = -1, frame;
    GLint vp[4], read_fbo, read_buf;
    unsigned char *pixels;
    char path[1024];
    FILE *f;

    if (interval < 0)
    {
        const char *env = getenv("GLCAPTURE_INTERVAL");
        dir = getenv("GLCAPTURE_DIR");
        interval = env ? atoi(env) : 60;
        if (interval < 1) interval = 1;
    }
    if (!dir || ++frame % interval) return;
    glGetIntegerv(GL_VIEWPORT, vp);
    if (vp[2] <= 0 || vp[3] <= 0 || !(pixels = malloc(vp[2] * vp[3] * 3))) return;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_fbo);
    glGetIntegerv(GL_READ_BUFFER, &read_buf);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    glReadBuffer(GL_BACK);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(vp[0], vp[1], vp[2], vp[3], GL_RGB, GL_UNSIGNED_BYTE, pixels);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fbo);
    glReadBuffer(read_buf);
    snprintf(path, sizeof(path), "%s/native-%d-%06d.ppm", dir, getpid(), frame);
    if ((f = fopen(path, "wb")))
    {
        fprintf(f, "P6\n%d %d\n255\n", vp[2], vp[3]);
        for (int y = vp[3] - 1; y >= 0; y--) fwrite(pixels + y * vp[2] * 3, 1, vp[2] * 3, f);
        fclose(f);
    }
    free(pixels);
}

static CGLError my_CGLFlushDrawable(CGLContextObj ctx)
{
    capture();
    return CGLFlushDrawable(ctx);
}
DYLD_INTERPOSE(my_CGLFlushDrawable, CGLFlushDrawable)

/* GLCAPTURE_INVARIANT=1: declare gl_Position invariant in every vertex shader. */
static void my_glShaderSource(GLuint shader, GLsizei count, const GLchar *const *string, const GLint *length)
{
    GLint type = 0;
    size_t total = 0, len = 0;
    char *src, *out, *nl;
    GLsizei i;

    glGetShaderiv(shader, GL_SHADER_TYPE, &type);
    if (!getenv("GLCAPTURE_INVARIANT") || type != GL_VERTEX_SHADER)
    {
        glShaderSource(shader, count, string, length);
        return;
    }
    for (i = 0; i < count; i++) total += length && length[i] >= 0 ? (size_t)length[i] : strlen(string[i]);
    src = malloc(total + 1);
    for (i = 0; i < count; i++)
    {
        size_t l = length && length[i] >= 0 ? (size_t)length[i] : strlen(string[i]);
        memcpy(src + len, string[i], l);
        len += l;
    }
    src[len] = 0;
    out = malloc(len + 64);
    if (!strncmp(src, "#version", 8) && (nl = strchr(src, '\n')))
    {
        size_t head = nl + 1 - src;
        memcpy(out, src, head);
        strcpy(out + head, "invariant gl_Position;\n");
        strcat(out, nl + 1);
    }
    else strcpy(out, src);
    {
        const GLchar *one = out;
        glShaderSource(shader, 1, &one, NULL);
    }
    free(out);
    free(src);
}
DYLD_INTERPOSE(my_glShaderSource, glShaderSource)
