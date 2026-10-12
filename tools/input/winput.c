/* winput: scripted input for automated game tests inside a Wine prefix.
 *
 *   winput.exe <window title> <cmd>...
 *     click X Y     left click at client coordinates
 *     move DX DY    relative mouse motion
 *     key VK        press and release a virtual key (decimal or 0x..)
 *     hold VK MS    hold a key for MS milliseconds
 *     type TEXT     type ASCII text
 *     sleep MS
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void send_mouse(DWORD flags, LONG x, LONG y)
{
    INPUT in = {0};
    in.type = INPUT_MOUSE;
    in.mi.dx = x;
    in.mi.dy = y;
    in.mi.dwFlags = flags;
    SendInput(1, &in, sizeof(in));
}

static void send_key(WORD vk, BOOL up)
{
    INPUT in = {0};
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    in.ki.wScan = MapVirtualKeyA(vk, MAPVK_VK_TO_VSC);
    in.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    SendInput(1, &in, sizeof(in));
}

int main(int argc, char **argv)
{
    HWND hwnd = NULL;
    for (int i = 0; i < 300 && !(hwnd = FindWindowA(NULL, argv[1])); i++) Sleep(100);
    if (!hwnd) { fprintf(stderr, "window \"%s\" not found\n", argv[1]); return 1; }
    SetForegroundWindow(hwnd);

    for (int i = 2; i < argc; i++)
    {
        if (!strcmp(argv[i], "click") && i + 2 < argc)
        {
            POINT pt = { atoi(argv[i + 1]), atoi(argv[i + 2]) };
            ClientToScreen(hwnd, &pt);
            SetCursorPos(pt.x, pt.y);
            Sleep(50);
            send_mouse(MOUSEEVENTF_LEFTDOWN, 0, 0);
            Sleep(80);
            send_mouse(MOUSEEVENTF_LEFTUP, 0, 0);
            i += 2;
        }
        else if (!strcmp(argv[i], "move") && i + 2 < argc)
        {
            int dx = atoi(argv[i + 1]), dy = atoi(argv[i + 2]);
            for (int s = 0; s < 10; s++) { send_mouse(MOUSEEVENTF_MOVE, dx / 10, dy / 10); Sleep(16); }
            i += 2;
        }
        else if (!strcmp(argv[i], "key") && i + 1 < argc)
        {
            WORD vk = strtol(argv[++i], NULL, 0);
            send_key(vk, FALSE); Sleep(60); send_key(vk, TRUE);
        }
        else if (!strcmp(argv[i], "hold") && i + 2 < argc)
        {
            WORD vk = strtol(argv[i + 1], NULL, 0);
            send_key(vk, FALSE); Sleep(atoi(argv[i + 2])); send_key(vk, TRUE);
            i += 2;
        }
        else if (!strcmp(argv[i], "type") && i + 1 < argc)
        {
            for (const char *p = argv[++i]; *p; p++)
            {
                SHORT v = VkKeyScanA(*p);
                if (v & 0x100) send_key(VK_SHIFT, FALSE);
                send_key(LOBYTE(v), FALSE); Sleep(30); send_key(LOBYTE(v), TRUE);
                if (v & 0x100) send_key(VK_SHIFT, TRUE);
                Sleep(30);
            }
        }
        else if (!strcmp(argv[i], "sleep") && i + 1 < argc)
            Sleep(atoi(argv[++i]));
        else { fprintf(stderr, "bad command %s\n", argv[i]); return 1; }
        Sleep(100);
    }
    return 0;
}
