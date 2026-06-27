项目概要：项目参考bilibiliup录播姬的抓取直播流概念，使用移动端flutter主动抓取直播间音频并保存为音频文件到本地。也参考项目Simple Live(https://github.com/xiaoyaocz/dart_simple_live)的多平台搜索功能。也参考项目bililive(https://github.com/BoooSAMA/bililive)的ffmpeg录取直播间音频的核心功能。

初期目标：结合Simple Live与bililive，取Simple Live的多平台访问功能，取bililive的录音功能。

初期主要实现的关键功能：
1.仅做为录播(音频)使用，移除观看直播间功能(包括弹幕相关功能)
2.并行录播(使用ffempeg)，同时录制多个直播间互不干扰对方(但不确定可行性)
3.仅给用户自行搜索直播间与收藏直播间，移除首页推荐页功能，尽可能偏向自定义工具化
4.每个直播间卡片显示debug log(可收起)
5.显示录播中的状态
6.刷新重连直播间功能
7.断线自动拼接
8.保证后台运行
9.简化报错提示
10.保存时自动存进主播名称的文件夹，没有就自动创建一个
11.写README时介绍录播功能仅限自用，目前禁止将录播文件分发至网上
