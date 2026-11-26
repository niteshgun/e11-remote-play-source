// e11: PSN sign-in in a native macOS WebKit window (see macPsnSignIn.h).
#include "macPsnSignIn.h"

#include <QString>

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#if __has_feature(objc_arc)
#define E11_RELEASE(x) do { (x) = nil; } while (0)
#else
#define E11_RELEASE(x) do { [(x) release]; (x) = nil; } while (0)
#endif

static bool E11IsPsnRedirect(NSURL *url)
{
	if (!url)
		return false;
	NSString *host = url.host.lowercaseString;
	return [host isEqualToString:@"remoteplay.dl.playstation.net"] && [url.path hasPrefix:@"/remoteplay/redirect"];
}

@interface E11PsnSignInController : NSObject <WKNavigationDelegate, WKUIDelegate, NSWindowDelegate>
{
@public
	std::function<void(const QUrl &)> onRedirect;
	std::function<void()> onClosed;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, strong) NSData *cryptoKey;
@end

static E11PsnSignInController *g_controller = nil;

@implementation E11PsnSignInController

- (void)openWithURL:(NSURL *)url
{
	NSRect frame = NSMakeRect(0, 0, 520, 720);
	self.window = [[NSWindow alloc] initWithContentRect:frame
	                                          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
	                                            backing:NSBackingStoreBuffered
	                                              defer:NO];
#if !__has_feature(objc_arc)
	[self.window release];
#endif
	self.window.title = @"Sign in with PlayStation Network";
	self.window.releasedWhenClosed = NO;
	self.window.delegate = self;
	self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
	self.window.backgroundColor = [NSColor colorWithSRGBRed:0.027 green:0.035 blue:0.047 alpha:1.0];

	WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
	// Normal browser storage: Sony's sign-in (Akamai) rejects the private store with "Can't connect
	// to the server". The keychain prompt is avoided by _webCryptoMasterKeyForWebView below instead.
	config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
	self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
#if !__has_feature(objc_arc)
	[config release];
	[self.webView release];
#endif
	// Sony's sign-in page refuses embedded web views ("Something went wrong"): present as Safari
	self.webView.customUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
	self.webView.navigationDelegate = self;
	self.webView.UIDelegate = self;
	self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	self.webView.underPageBackgroundColor = self.window.backgroundColor;
	self.window.contentView = self.webView;

	self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(frame.size.width / 2 - 16, frame.size.height / 2 - 16, 32, 32)];
#if !__has_feature(objc_arc)
	[self.spinner release];
#endif
	self.spinner.style = NSProgressIndicatorStyleSpinning;
	self.spinner.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
	[self.webView addSubview:self.spinner];
	[self.spinner startAnimation:nil];

	[self.window center];
	[self.window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
	[self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)finishWithURL:(NSURL *)url
{
	if (self.finished)
		return;
	self.finished = YES;
	QUrl qurl = QUrl(QString::fromNSString(url.absoluteString));
	auto cb = onRedirect;
	[self.window orderOut:nil];
	[self.window close];
	if (cb)
		cb(qurl);
}

// Sony's page stores WebCrypto keys. Without this, WebKit keeps a "WebCrypto Master Key" in the
// login keychain and macOS asks for the Mac password whenever the app's signature changes.
// We hand WebKit a random key that only lives for this sign-in window (storage is in-memory anyway),
// so the keychain is never touched.
- (NSData *)e11MasterKey
{
	if (!self.cryptoKey) {
		uint8_t bytes[16];
		arc4random_buf(bytes, sizeof bytes);
		self.cryptoKey = [NSData dataWithBytes:bytes length:sizeof bytes];
	}
	return self.cryptoKey;
}

- (NSData *)_webCryptoMasterKeyForWebView:(WKWebView *)webView
{
	return [self e11MasterKey];
}

- (void)_webCryptoMasterKeyForWebView:(WKWebView *)webView completionHandler:(void (^)(NSData *))completionHandler
{
	completionHandler([self e11MasterKey]);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	NSURL *url = action.request.URL;
	if (E11IsPsnRedirect(url)) {
		decisionHandler(WKNavigationActionPolicyCancel);
		[self finishWithURL:url];
		return;
	}
	decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation
{
	if (E11IsPsnRedirect(webView.URL)) {
		NSURL *url = webView.URL;
		[webView stopLoading];
		[self finishWithURL:url];
	}
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
	[self.spinner stopAnimation:nil];
	self.spinner.hidden = YES;
}

// Sony's page sometimes opens links in a new window (help, privacy): load them in place
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features
{
	if (action.request.URL)
		[webView loadRequest:action.request];
	return nil;
}

- (void)windowWillClose:(NSNotification *)note
{
	self.webView.navigationDelegate = nil;
	self.webView.UIDelegate = nil;
	[self.webView stopLoading];
	if (!self.finished && onClosed) {
		self.finished = YES;
		auto cb = onClosed;
		cb();
	}
	// Free the controller after this run-loop pass (we are inside its own delegate call)
	E11PsnSignInController *me = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (g_controller == me) {
			E11_RELEASE(g_controller);
		}
	});
}

@end

namespace MacPsnSignIn
{

void Start(const QUrl &loginUrl, std::function<void(const QUrl &)> onRedirect, std::function<void()> onClosed)
{
	if (g_controller && g_controller.window.isVisible) {
		g_controller->onRedirect = onRedirect;
		g_controller->onClosed = onClosed;
		[g_controller.window makeKeyAndOrderFront:nil];
		return;
	}
	if (g_controller) {
		E11_RELEASE(g_controller);
	}
	g_controller = [[E11PsnSignInController alloc] init];
	g_controller->onRedirect = onRedirect;
	g_controller->onClosed = onClosed;
	NSURL *url = [NSURL URLWithString:loginUrl.toString(QUrl::FullyEncoded).toNSString()];
	[g_controller openWithURL:url];
}

void Close()
{
	if (!g_controller)
		return;
	g_controller->onRedirect = nullptr;
	g_controller->onClosed = nullptr;
	g_controller.finished = YES;
	[g_controller.window close];
}

}
