
// NetPeek.m - in-app traffic viewer. No proxy, no certs, no FLEX.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface NetPeek : NSObject
+ (void)start;
@end

static NSMutableArray *gLog;
static NSMutableArray *gSeen;
static UIWindow *gWin;

static void NPAdd(NSString *s) {
    if (!s) return;
    if (!gLog) gLog = [NSMutableArray array];
    @synchronized (gLog) {
        [gLog insertObject:s atIndex:0];
        while (gLog.count > 400) [gLog removeLastObject];
    }
}

static BOOL NPIsHTTP(NSURL *u) {
    NSString *s = u.scheme.lowercaseString;
    return [s isEqualToString:@"http"] || [s isEqualToString:@"https"];
}

static NSString *NPBody(NSData *d) {
    if (!d.length) return @"(empty)";
    NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!t) return [NSString stringWithFormat:@"(%lu bytes binary)", (unsigned long)d.length];
    if (t.length > 4000) return [t substringToIndex:4000];
    return t;
}

static NSString *NPHeaders(NSDictionary *h) {
    if (!h.count) return @"";
    NSMutableString *m = [NSMutableString string];
    for (id k in h) [m appendFormat:@"%@: %@\n", k, h[k]];
    return m;
}

static void NPLogRequest(NSURLRequest *r) {
    if (![r isKindOfClass:[NSURLRequest class]]) return;
    if (!NPIsHTTP(r.URL)) return;
    if (!gSeen) gSeen = [NSMutableArray array];
    @synchronized (gSeen) {
        for (NSValue *v in gSeen) if (v.pointerValue == (__bridge void *)r) return;
        [gSeen addObject:[NSValue valueWithPointer:(__bridge void *)r]];
        if (gSeen.count > 500) [gSeen removeObjectAtIndex:0];
    }
    NPAdd([NSString stringWithFormat:@"\n>>> %@ %@\n%@\n%@",
           r.HTTPMethod ?: @"GET", r.URL.absoluteString,
           NPHeaders(r.allHTTPHeaderFields), NPBody(r.HTTPBody)]);
}

static void NPLogResponse(NSURLResponse *resp, NSData *data) {
    if (![resp isKindOfClass:[NSHTTPURLResponse class]]) return;
    NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
    NPAdd([NSString stringWithFormat:@"<<< %ld %@\n%@\n%@",
           (long)h.statusCode, h.URL.absoluteString, NPHeaders(h.allHeaderFields), NPBody(data)]);
}

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
    self.tv.separatorColor = [UIColor darkGrayColor];
    [self.view addSubview:self.tv];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)refresh {
    self.rows = [gLog copy] ?: @[];
    [self.tv reloadData];
}
- (void)clear { @synchronized (gLog) { [gLog removeAllObjects]; } [self refresh]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.backgroundColor = [UIColor blackColor];
    c.textLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    c.textLabel.numberOfLines = 6;
    c.textLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    c.textLabel.text = self.rows[i.row];
    return c;
}
@end

@interface NPButton : UIButton
@end

@implementation NPButton
- (void)go {
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
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

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h {
    NPLogRequest(request);
    if (!h) return %orig;
    return %orig(request, ^(NSData *d, NSURLResponse *r, NSError *e) {
        NPLogResponse(r, d);
        h(d, r, e);
    });
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NPLogRequest(request);
    return %orig;
}
%end

%hook NSURLConnection
+ (NSURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    NPLogRequest(request);
    return %orig;
}
%end

@implementation NetPeek
+ (void)start {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGRect scr = UIScreen.mainScreen.bounds;
        gWin = [[UIWindow alloc] initWithFrame:scr];
        gWin.windowLevel = UIWindowLevelAlert + 1;
        gWin.backgroundColor = [UIColor clearColor];
        gWin.rootViewController = [[UIViewController alloc] init];
        [gWin makeKeyAndVisible];

        NPButton *b = [NPButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(scr.size.width - 62, scr.size.height * 0.3, 46, 46);
        b.backgroundColor = [UIColor colorWithRed:0.1 green:0.35 blue:0.9 alpha:0.85];
        b.layer.cornerRadius = 23;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        b.titleLabel.numberOfLines = 2;
        [b setTitle:@"NET\nPEEK" forState:UIControlStateNormal];
        [b addTarget:b action:@selector(go) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:b action:@selector(drag:)]];
        [gWin.rootViewController.view addSubview:b];
    });
}
@end

%ctor {
    [NetPeek start];
}
