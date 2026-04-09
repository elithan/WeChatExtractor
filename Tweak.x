#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface MMUIViewController : UIViewController
- (void)handleIconExtractionGesture:(UILongPressGestureRecognizer *)gesture;
@end

@interface UIImage (Private)
@property (nonatomic, readonly) NSString *imageAsset;
@end

@interface WeChatExtractor : NSObject
+ (void)extractFromView:(UIView *)view;
@end

@implementation WeChatExtractor

+ (void)extractFromView:(UIView *)view {
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *exportPath = [docsPath stringByAppendingPathComponent:@"ExtractedIcons"];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:exportPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSMutableArray *results = [NSMutableArray array];
    [self traverseView:view exportPath:exportPath results:results];
    
    NSString *logPath = [exportPath stringByAppendingPathComponent:@"extraction_log.txt"];
    [results.description writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Extraction Complete"
                                                                   message:[NSString stringWithFormat:@"Extracted to: %@", exportPath]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

+ (void)traverseView:(UIView *)view exportPath:(NSString *)exportPath results:(NSMutableArray *)results {
    // 检查 UIImageView
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        [self saveImage:imageView.image fromView:view exportPath:exportPath results:results];
    } 
    // 检查 UIButton
    else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        [self saveImage:button.currentImage fromView:view exportPath:exportPath results:results];
        [self saveImage:button.currentBackgroundImage fromView:view exportPath:exportPath results:results];
    }
    // 检查微信自定义的 SVG 视图类 (例如 WCSvgView)
    else if ([NSStringFromClass([view class]) containsString:@"Svg"]) {
        // 尝试通过私有方法获取 image 或 data
        if ([view respondsToSelector:@selector(image)]) {
            UIImage *img = [view performSelector:@selector(image)];
            [self saveImage:img fromView:view exportPath:exportPath results:results];
        }
    }
    
    for (UIView *subview in view.subviews) {
        [self traverseView:subview exportPath:exportPath results:results];
    }
}

+ (void)saveImage:(UIImage *)image fromView:(UIView *)view exportPath:(NSString *)exportPath results:(NSMutableArray *)results {
    if (!image) return;
    
    NSString *imageName = @"icon";
    // 尝试从 UIImageAsset 中提取资源名称 (私有方法)
    if ([image respondsToSelector:@selector(imageAsset)]) {
        id asset = [image valueForKey:@"imageAsset"];
        if ([asset respondsToSelector:@selector(assetName)]) {
            imageName = [asset valueForKey:@"assetName"] ?: @"icon";
        }
    }
    
    // 生成唯一文件名
    NSString *timestamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] * 1000];
    NSString *ext = @"png"; // 默认导出为 PNG
    
    // 记录详情
    NSDictionary *info = @{
        @"name": imageName,
        @"size": NSStringFromCGSize(image.size),
        @"view_class": NSStringFromClass([view class]),
        @"view_frame": NSStringFromCGRect(view.frame),
        @"timestamp": timestamp
    };
    [results addObject:info];
    
    // 保存 PNG 数据
    NSString *fileName = [NSString stringWithFormat:@"%@_%@.%@", imageName, timestamp, ext];
    NSString *filePath = [exportPath stringByAppendingPathComponent:fileName];
    NSData *imageData = UIImagePNGRepresentation(image);
    if (imageData) {
        [imageData writeToFile:filePath atomically:YES];
    }
}

@end

%hook MMUIViewController // WeChat's base view controller

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // Add a long press gesture to trigger extraction if it doesn't exist
    BOOL hasGesture = NO;
    for (UIGestureRecognizer *g in self.view.gestureRecognizers) {
        if ([g isKindOfClass:[UILongPressGestureRecognizer class]] && [g.name isEqualToString:@"IconExtractorGesture"]) {
            hasGesture = YES;
            break;
        }
    }
    
    if (!hasGesture) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleIconExtractionGesture:)];
        longPress.name = @"IconExtractorGesture";
        longPress.minimumPressDuration = 2.0; // 2 seconds
        [self.view addGestureRecognizer:longPress];
    }
}

%new
- (void)handleIconExtractionGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [WeChatExtractor extractFromView:self.view];
    }
}

%end
