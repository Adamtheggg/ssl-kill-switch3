
// NetPeek.x - in-app traffic viewer. No proxy, no certs, no FLEX.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define NP_MARK @"X-NetPeek"

static NSMutableArray *gLog;
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
    if (!d.length) return @"(none)";
    NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!t) return [NSString stringWithFormat:@"(%lu bytes binary)", (unsigned long)d.length];
    return t;
}

// read a body stream without consuming it for the real request
static NSData *NPReadStream(NSInputStream *in, NSMutableURLRequest *m) {
    if (!in) return nil;
    [in open];
    NSMutableData *out = [NSMutableData data];
    uint8_t buf[4096];
    NSInteger n = 0;
    while ((n = [in read:buf maxLength:sizeof(buf)]) > 0) {
        [out appendBytes:buf length:n];
        if (out.length > 400000) break;
    }
    [in close];
    if (m && out.length) m.HTTPBodyStream = [NSInputStream inputStreamWithData:out];
    return out;
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
    NSMutableURLRequest *m = [self.request mutableCopy];
    NSData *reqBody = nil;
    if (m.HTTPBody) {
        reqBody = m.HTTPBody;
    } else if (m.HTTPBodyStream) {
        reqBody = NPReadStream(m.HTTPBodyStream, m);
    }
    NPAdd([NSString stringWithFormat:@"\n>>> %@ %@\n\n-- headers --\n%@\n-- body --\n%@",
           m.HTTPMethod ?: @"GET", m.URL.absoluteString,
           NPHeaders(m.allHTTPHeaderFields), NPBody(reqBody)]);
    [NSURLProtocol setProperty:@YES forKey:NP_MARK inRequest:m];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    __weak typeof(self) w = self;
    [[s dataTaskWithRequest:m completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        __strong typeof(w) me = w; if (!me) return;
        if (e) { [me.client URLProtocol:me didFailWithError:e]; return; }
        if ([r isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *h = (NSHTTPURLResponse *)r;
            NSData *dec = d;
            NSString *enc = [h.allHeaderFields[@"Content-Encoding"] lowercaseString];
            if ([enc containsString:@"gzip"]) {
                dec = [d isKindOfClass:[NSData class]] ? d : nil;
            }
            NPAdd([NSString stringWithFormat:@"\n<<< %ld %@\n\n-- headers --\n%@\n-- body --\n%@",
                   (long)h.statusCode, h.URL.absoluteString, NPHeaders(h.allHeaderFields), NPBody(dec)]);
        }
        [me.client URLProtocol:me didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [me.client URLProtocol:me didLoadData:d];
        [me.client URLProtocolDidFinishLoading:me];
    }] resume];
}
- (void)stopLoading {}
@end

@interface NPDVC : UIViewController
@property (nonatomic, copy) NSString *text;
@end

@implementation NPDVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Details";
    self.view.backgroundColor = [UIColor blackColor];
    UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor whiteColor];
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.editable = NO;
    tv.text = self.text;
    [self.view addSubview:tv];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStyleDone target:self action:@selector(copyAll)];
}
- (void)copyAll { [UIPasteboard generalPasteboard].string = self.text; }
@end

@interface NPVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
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
    self.tv.delegate = self;
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
    c.textLabel.numberOfLines = 5;
    c.textLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    c.textLabel.text = self.rows[i.row];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i {
    [t deselectRowAtIndexPath:i animated:YES];
    NPDVC *d = [[NPDVC alloc] init];
    d.text = self.rows[i.row];
    [self.navigationController pushViewController:d animated:YES];
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
