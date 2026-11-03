//
//  DKFontStore.h
//  字体：导入的字体文件只存一份（Library/Application Support/DKXSFonts/），
//  注册到当前进程后替换界面里的系统字体；恢复默认即注销并删除文件。
//

#ifndef DKFontStore_h
#define DKFontStore_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 已导入字体文件的 URL（文件不存在时仍返回路径）。
NSURL *DKFontFileURL(void);

/// 当前已导入字体的原文件名，没有导入时返回 nil。
NSString *DKFontCurrentDisplayName(void);

/// 已注册字体的 PostScript 名，没有导入/注册失败时返回 nil。
NSString *DKFontRegisteredPostScriptName(void);

/// 校验并保存字体数据（.ttf/.otf/.ttc，32MB 以内），保存成功后注册。
/// 失败返回 NO 并在 reason 中说明原因（data 为 nil、格式不对、写盘失败等）。
BOOL DKFontStoreData(NSData *data, NSString *fileName, NSString **reason);

/// 启动时注册已保存的字体（没有保存文件时什么也不做）。
void DKFontRegisterStoredFont(void);

/// 注销已注册的字体并删除文件与记录，恢复系统默认字体。
void DKFontRestoreDefault(void);

#ifdef __cplusplus
}
#endif

#endif /* DKFontStore_h */
