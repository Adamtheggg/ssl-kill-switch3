
// NetPeek.x - in-app traffic viewer. No proxy, no certs, no FLEX.
// Capture via NSURLProtocol. Button added directly to key window.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define NP_MARK @"X-NetPeek"

static NSMutableArray *gLog;
static NSMutableArray *gSeen;
static UIButton *gBtn;

static void NPAdd(NSString *s) {
    if (!s) return;
    if (!gLog) gLog = [NSMutableArray array];
    @synchronized (gLog) {
        [gLog insertObject:s atIndex:0];
        while (gLog.count > 300) [gLog removeLastObject];
    }
}

static NSString *NPBody(NSData *d) {
    if (!d.length) return @"(empty)";
    NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!t) return [NSString stringWithFormat:@"(%lu bytes)", (unsigned long)d.length];
    if (t.length > 3000) return [t substringToIndex:3000];
    return t;
}

static NSString *NPHeaders(NSDictionary *h) {
    if (!h.count) return @"";
    NSMutableString *m = [NSMutableString string];
    for (id k in h) [m appendFormat:@"%@: %@\n", k, h[k]];
    return m;
}

@interface NPProto : NSURLProtocol @end
@implementation NPProto
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    if ([NSURLProtocol propertyForKey:NP_MARK inRequest:r]) return NO;
    NSString *s = r.URL.scheme.lowercaseString;
    return [s isEqualToString:@"http"] || [s isEqualToString:@"https"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSURLRequest *req = self.request;
    NPAdd([NSString stringWithFormat:@"\n>>> %@ %@\n%@\n%@",
           req.HTTPMethod ?: @"GET", req.URL.absoluteString,
           NPHeaders(req.allHTTPHeaderFields), NPBody(req.HTTPBody)]);
    NSMutableURLRequest *m = [req mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:NP_MARK inRequest:m];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    __weak typeof(self) w = self;
    [[s dataTaskWithRequest:m completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        __strong typeof(w) me = w; if (!me) return;
        if (e) { [me.client URLProtocol:me didFailWithError:e]; return; }
        if ([r isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *h = (NSHTTPURLResponse *)r;
            NPAdd([NSString stringWithFormat:@"<<< %ld %@\n%@\n%@",
                   (long)h.statusCode, h.URL.absoluteString, NPHeaders(h.allHeaderFields), NPBody(d)]);
        }
        [me.client URLProtocol:me didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [me.client URLProtocol:me didLoadData:d];
        [me.client URLProtocolDidFinishLoading:me];
    }] resume];
}
- (void)stopLoading {}
@end

@interface NPVC : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *tv;
@property (nonatomic, strong) NSArray *rows;
@end

@implementation NPVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NetPeek";
    self.view.backgroundColor = [UIColor blackColor];
    self.tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tv.dataSource = self;
    self.tv.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.tv];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)refresh { self.rows = [gLog copy] ?: @[]; [self.tv reloadData]; }
- (void)clear { @synchronized (gLog) { [gLog removeAllObjects]; } [self refresh]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.backgroundColor = [UIColor blackColor];
    c.textLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    c.textLabel.numberOfLines = 8;
    c.textLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    c.textLabel.text = self.rows[i.row];
    return c;
}
@end

@interface NPButton : UIButton @end
@implementation NPButton
- (void)go {
    UIWindow *w = nil;
    for (UIWindow *x in UIApplication.sharedApplication.windows) { if (x.isKeyWindow) { w = x; break; } }
    if (!w) w = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return;
    NPVC *v = [[NPVC alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:v];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:nav animated:YES completion:nil];
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + p.x, self.center.y + p.y);
    [g setTranslation:CGPointZero inView:self.superview];
}
@end

static void NPInstall(void) {
    if (gBtn && gBtn.superview) return;
    UIWindow *host = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) { if (w.isKeyWindow) { host = w; break; } }
    if (!host) host = UIApplication.sharedApplication.windows.firstObject;
    if (!host) return;
    CGRect f = host.bounds;
    gBtn = [NPButton buttonWithType:UIButtonTypeCustom];
    gBtn.frame = CGRectMake(f.size.width - 58, f.size.height * 0.35, 44, 44);
    gBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.35 blue:0.9 alpha:0.9];
    gBtn.layer.cornerRadius = 22;
    gBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    gBtn.titleLabel.numberOfLines = 2;
    [gBtn setTitle:@"NET\nPEEK" forState:UIControlStateNormal];
    [gBtn addTarget:gBtn action:@selector(go) forControlEvents:UIControlEventTouchUpInside];
    [gBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:gBtn action:@selector(drag:)]];
    [host addSubview:gBtn];
    [host bringSubviewToFront:gBtn];
}

static void NPBootstrap(void) {
    for (int i = 0; i < 10; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NPInstall();
        });
    }
}

%ctor {
    [NSURLProtocol registerClass:objc_getClass("NPProto")];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { NPBootstrap(); }];
    NPBootstrap();
}
