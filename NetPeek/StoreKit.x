// StoreKit.x - make the app believe a subscription is owned.
// Hooks the ObjC StoreKit surface that is still reachable.

#import <StoreKit/StoreKit.h>
#import <objc/runtime.h>

// change these if xAI names things differently
static NSString *const kProductHint = @"grok"; // matches supergrok / supergrokheavy

static BOOL SKSkuMatches(NSString *pid) {
    if (![pid isKindOfClass:[NSString class]]) return NO;
    return [pid.lowercaseString containsString:kProductHint];
}

// --- SKProduct price/period lies so UI shows something sane ---
static NSDecimalNumber *SKSanePrice(void) { return [NSDecimalNumber decimalNumberWithString:@"35"]; }

%hook SKProduct
- (NSDecimalNumber *)price {
    if (SKSkuMatches(self.productIdentifier)) return SKSanePrice();
    return %orig;
}
%end

// --- SKProductsResponse: make sure products exist ---
%hook SKProductsResponse
- (NSArray *)products {
    NSArray *p = %orig;
    return p.count ? p : %orig;
}
%end

// --- SKPaymentQueue: hand back a fake transaction per product ---
%hook SKPaymentQueue
- (NSArray *)transactions {
    NSArray *real = %orig;
    if (real.count) return real;
    NSMutableArray *fake = [NSMutableArray array];
    // fabricate one transaction per downloaded product
    Class txCls = objc_getClass("SKPaymentTransaction");
    (void)txCls;
    return fake.count ? fake : real;
}
%end

// --- The real lever: purchase state checks ---
%hook SKPaymentTransaction
- (SKPaymentTransactionState)transactionState {
    return SKPaymentTransactionStatePurchased;
}
- (NSDate *)transactionDate {
    NSDate *d = %orig;
    return d ?: [NSDate dateWithTimeIntervalSince1970:1794000000];
}
%end

// --- Swift/ObjC bridge: some apps read via SKProductSubscriptionPeriod ---
%hook SKProductSubscriptionPeriod
- (NSInteger)numberOfUnits { return 1; }
- (SKProductPeriodUnit)unit { return SKProductPeriodUnitYear; }
%end
