//
//  APMController.m
//  Worldpay
//
//  Copyright (c) 2015 Worldpay. All rights reserved.
//
@import WebKit;

#import "APMController.h"
#import "Worldpay.h"

@interface APMController () <WKNavigationDelegate>

@property (nonatomic, copy) authorizeAPMOrderSuccess authorizeSuccessBlock;
@property (nonatomic, copy) authorizeAPMOrderFailure authorizeFailureBlock;

@property (nonatomic, copy) NSString *currentOrderCode;
@property (nonatomic, copy) WKWebView *webView;

@property (nonatomic, strong) NSURLSession *networkManager;

@end

@implementation APMController

- (instancetype)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        
        NSURLSession *networkManager = [NSURLSession sessionWithConfiguration:configuration];
        _networkManager = networkManager;
    }
    
    return self;
}

- (void)dealloc {
    [self.networkManager invalidateAndCancel];
}

- (void)createNavigationBar {
    
    if (_customToolbar) {
        [self.view addSubview:_customToolbar];
        return;
    }
    
    UIView *navigationBarView = [[UIView alloc]initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 50)];
    navigationBarView.backgroundColor = [UIColor colorWithRed:224.0/255.0 green:224.0/255.0 blue:224.0/255.0 alpha:1.0];
    _customToolbar = navigationBarView;
    [self.view addSubview:navigationBarView];
    
    UIButton *closeBtn = [[UIButton alloc] initWithFrame:CGRectMake(0, 15, 80, 30)];
    [closeBtn setTitleColor:self.view.tintColor forState:UIControlStateNormal];
    
    [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
    [navigationBarView addSubview:closeBtn];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self createNavigationBar];
    
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    _webView = [[WKWebView alloc] initWithFrame:CGRectMake(0.0,50,self.view.frame.size.width,self.view.frame.size.height-_customToolbar.frame.size.height)
                                            configuration:config];
    _webView.navigationDelegate = self;
    
    [self.view addSubview:_webView];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self initializeAPM];
}

- (IBAction)close:(id)sender {
    
    NSMutableArray *errors = [[NSMutableArray alloc] init];
    [errors addObject:[[Worldpay sharedInstance] errorWithTitle:NSLocalizedString(@"User cancelled APM authorization", nil) code:0]];
    _authorizeFailureBlock(@{}, errors);
    
    if (!self.navigationController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    else {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
}


#pragma mark - APM Methods

- (void)initializeAPM {
    NSString *stringURL = [[[Worldpay sharedInstance] APIStringURL] stringByAppendingPathComponent:@"orders"];
    
    NSDictionary *params = @{
                             @"token": _token,
                             @"orderDescription": _orderDescription,
                             @"amount": @((float)(ceil(_price * 100))),
                             @"currencyCode": _currencyCode,
                             @"settlementCurrency": _settlementCurrency,
                             @"name": _name,
                             @"billingAddress": @{
                                     @"address1": _address,
                                     @"postalCode": _postalCode,
                                     @"city": _city,
                                     @"countryCode": _countryCode
                                     },
                             @"customerIdentifiers": (_customerIdentifiers && _customerIdentifiers.count > 0) ? _customerIdentifiers : @{},
                             @"customerOrderCode": _customerOrderCode,
                             @"is3DSOrder": @(NO),
                             @"successUrl": _successUrl,
                             @"pendingUrl": _pendingUrl,
                             @"failureUrl": _failureUrl,
                             @"cancelUrl": _cancelUrl
                             };
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:stringURL]];
    [request setHTTPMethod:@"POST"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:params options:NSJSONWritingFragmentsAllowed error:nil];
    request.HTTPBody = data;
    
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request addValue:[Worldpay sharedInstance].serviceKey forHTTPHeaderField:@"Authorization"];
    __weak typeof(self) weak = self;
    
    NSURLSessionDataTask *dataTask = [self.networkManager dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        id responseObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if ([[responseObject objectForKey:@"paymentStatus"] isEqualToString:@"PRE_AUTHORIZED"]) {
            weak.currentOrderCode = [responseObject objectForKey:@"orderCode"];
            
            //Refresh URLS in case the user doesn't input any urls on create order
            weak.successUrl = [responseObject objectForKey:@"successUrl"];
            weak.failureUrl = [responseObject objectForKey:@"failureUrl"];
            weak.cancelUrl = [responseObject objectForKey:@"cancelUrl"];
            weak.pendingUrl = [responseObject objectForKey:@"pendingUrl"];
            
            [weak redirectToAPMPageWithRedirectURL:[responseObject objectForKey:@"redirectURL"]];
            
        } else {
            NSMutableArray *errors = [[NSMutableArray alloc] init];
            [errors addObject:[[Worldpay sharedInstance] errorWithTitle:NSLocalizedString(@"There was an error creating the APM Order.", nil) code:1]];
            
            
            weak.authorizeFailureBlock(responseObject, errors);
        }
    }];
    [dataTask resume];
}

- (void)redirectToAPMPageWithRedirectURL:(NSString *)redirectURL {
    NSURL *url = [NSURL URLWithString:redirectURL];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL: url];
    request.HTTPMethod = @"GET";
    
    [_webView loadRequest: request];
}

- (void)setAuthorizeAPMOrderBlockWithSuccess:(authorizeAPMOrderSuccess)success
                                     failure:(authorizeAPMOrderFailure)failure {
    _authorizeSuccessBlock = success;
    _authorizeFailureBlock = failure;
}

#pragma mark - WKWebView delegate methods

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL *url = navigationAction.request.URL;
    
    NSDictionary *responseDictionary = @{
                                         @"token": _token,
                                         @"orderCode": _currentOrderCode
                                         };
    NSMutableArray *errors = [[NSMutableArray alloc] init];
    
    //we need to tell the parent controller that the purchase was success
    if ([url.absoluteString containsString:_successUrl]) {
        _authorizeSuccessBlock(responseDictionary);
    }
    else if ([url.absoluteString containsString:_failureUrl]) {
        [errors addObject:[[Worldpay sharedInstance] errorWithTitle:NSLocalizedString(@"There was an error authorizing the APM Order. Order failed.", nil) code:1]];
        _authorizeFailureBlock(responseDictionary, errors);
    }
    else if ([url.absoluteString containsString:_cancelUrl]) {
        [errors addObject:[[Worldpay sharedInstance] errorWithTitle:NSLocalizedString(@"There was an error authorizing the APM Order. Order cancelled.", nil) code:2]];
        _authorizeFailureBlock(responseDictionary, errors);
    }
    else if ([url.absoluteString containsString:_pendingUrl]) {
        [errors addObject:[[Worldpay sharedInstance] errorWithTitle:NSLocalizedString(@"There was an error authorizing the APM Order. Order pending.", nil) code:3]];
        _authorizeFailureBlock(responseDictionary, errors);
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

@end
