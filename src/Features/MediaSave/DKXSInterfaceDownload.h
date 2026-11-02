//
//  DKXSInterfaceDownload.h
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  接口解析保存媒体的独立执行端，移植自 Wtrwx/DYYY 的
//  DYYYManager parseAndDownloadVideoWithShareLink + handleVideoData
//  （核心流程原样：接口 URL = apiKey + 百分号编码后的分享链接；
//  JSON code 为 0 或 200 才继续；dataDict 交 handleVideoData 处理）。
//
//  与上游的两个不同点（见 REPORT）：
//  1. 清晰度选择不用 AWEUserActionSheetView，改用系统 UIAlertController，
//     不依赖 40.8.0 里该面板类是否存活；选择逻辑与上游一致
//     （开 DKXSShowAllVideoQuality 才弹选择，否则直接下载）。
//  2. 真正的下载/相册写入不用 DYYYManager 的 downloadMedia 全套，
//     改用 DYxs 现有的 DKMediaDownloader + DKMediaLibrary（视频可补音轨）。
//
//  调用方说明（重要）：本文件只提供执行端，当前没有任何菜单调用它。
//  上游的调用点是长按面板里的“接口保存”项（DYYYLongPressPanel.xm
//  341/1112 行，enableApiDownload 门控）与双击菜单的同名项，
//  均不在本批范围内；主 agent 需在第 4 批长按面板项合并时
//  把“接口保存”项接到本 helper（取当前作品 shareURL 调本方法），
//  否则 DKXSInterfaceDownload / DKXSShowAllVideoQuality 两键登记了也跑不起来。
//

#import <Foundation/Foundation.h>

@interface DKXSInterfaceDownload : NSObject
+ (void)parseAndDownloadWithShareLink:(NSString *)shareLink;
@end
