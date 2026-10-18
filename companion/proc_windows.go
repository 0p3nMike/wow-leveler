//go:build windows

package main

import (
	"strings"
	"syscall"
	"unsafe"
)

// running reports whether a process with this exe name is running.
func running(exe string) bool {
	snap, err := syscall.CreateToolhelp32Snapshot(syscall.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return false
	}
	defer syscall.CloseHandle(snap)
	var e syscall.ProcessEntry32
	e.Size = uint32(unsafe.Sizeof(e))
	for err = syscall.Process32First(snap, &e); err == nil; err = syscall.Process32Next(snap, &e) {
		if strings.EqualFold(syscall.UTF16ToString(e.ExeFile[:]), exe) {
			return true
		}
	}
	return false
}
