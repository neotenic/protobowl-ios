
#import "MainViewController.h"
#import "SocketIOJSONSerialization.h"
#import "LinedTextView.h"
#import "GuessViewController.h"
#import "UIFont+FontAwesome.h"
#import "NSString+FontAwesome.h"
#import "iOS7ProgressView.h"
#import <QuartzCore/QuartzCore.h>
#import "UIView+Donald.h"
#import "PulloutView.h"
#import "SideMenuViewController.h"

/*#define LOG(s, ...) do { \
    NSString *string = [NSString stringWithFormat:s, ## __VA_ARGS__]; \
    NSLog(@"%@", string); \
    [self logToTextView:string]; \
} while(0)*/

@interface MainViewController ()
@property (weak, nonatomic) IBOutlet UILabel *questionTextView;
@property (weak, nonatomic) IBOutlet UIView *questionContainerView;
@property (weak, nonatomic) IBOutlet LinedTextView *textViewLog;
@property (nonatomic, strong) ProtobowlConnectionManager *manager;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *questionContainerHeightConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *questionTextHeightConstraint;
@property (weak, nonatomic) IBOutlet iOS7ProgressView *timeBar;
@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UIButton *buzzButton;
@property (weak, nonatomic) IBOutlet UILabel *answerLabel;

@property (weak, nonatomic) IBOutlet UIView *contentView;
@property (nonatomic) float lastTransitionOffset;
@property (nonatomic) BOOL isAnimating;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *backgroundVerticalSpace;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *backgroundHorizontalSpace;
@property (weak, nonatomic) IBOutlet UIImageView *backgroundImageView;
@property (nonatomic) BOOL isNextAnimationEnabled;

@property (weak, nonatomic) IBOutlet PulloutView *scorePulloutView;
@property (nonatomic) float pulloutStartX;
@property (nonatomic) float sideMenuStartX;

@property (strong, nonatomic) SideMenuViewController *sideMenu;

@property (nonatomic) BOOL isSideMenuOnScreen;

@property (weak, nonatomic) IBOutlet UILabel *myInfoLabel;
@property (weak, nonatomic) IBOutlet UILabel *myScoreLabel;
@end

@implementation MainViewController

#pragma mark - View Controller Life Cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.answerLabel.text = @"";
    self.timeLabel.text = @"";
    
    self.manager = [[ProtobowlConnectionManager alloc] init];
    self.manager.roomDelegate = self;
    
    [self.manager connect];
    
    // Setup and stylize question text view
    self.questionContainerView.frame = CGRectMake(0, 0, self.questionContainerView.frame.size.width, 200);
    [self.questionContainerView applySinkStyleWithInnerColor:nil borderColor:[UIColor colorWithWhite:227/255.0 alpha:1.0] borderWidth:1.0 andCornerRadius:10.0];
    
    // Setup attributed string with bell glyph on buzz button
    NSString *bell = [NSString fontAwesomeIconStringForEnum:FAIconBell];
    NSString *buzzText = [NSString stringWithFormat:@"   %@ Buzz", bell];
    NSMutableAttributedString *attributedBuzzText = [[NSMutableAttributedString alloc] initWithString:buzzText];
    
    UIFont *buzzFont = [UIFont fontWithName:@"HelveticaNeue-Light" size:20];
    
    [attributedBuzzText setAttributes:@{NSFontAttributeName : buzzFont,
                                        NSForegroundColorAttributeName : [UIColor whiteColor]} range:NSMakeRange(0, buzzText.length)];
    [attributedBuzzText setAttributes:@{NSFontAttributeName: [UIFont iconicFontOfSize:20],
                                        NSForegroundColorAttributeName : [UIColor whiteColor]} range:[buzzText rangeOfString:bell]];
    
    [self.buzzButton setAttributedTitle:attributedBuzzText forState:UIControlStateNormal];
    
    // Setup timer bar
    self.timeBar.progressColor = [UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0];
    self.timeBar.trackColor = [UIColor colorWithRed:184/255.0 green:184/255.0 blue:184/255.0 alpha:1.0];
    
    // Setup next question swipe gesture
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(animateToNextQuestion)];
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    [self.view addGestureRecognizer:swipe];
    
    // Setup pullout pan and tap gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.scorePulloutView addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [self.scorePulloutView addGestureRecognizer:tap];
    
    
    // Setup side menu view and view controller offscreen
    self.sideMenu = [self.storyboard instantiateViewControllerWithIdentifier:@"SideMenuViewController"];
    self.sideMenu.mainViewController = self;
    [self addChildViewController:self.sideMenu];
    
    
    UIView *sideMenuView = self.sideMenu.view;
    sideMenuView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sideMenuView];
    
    NSNumber *width = @([[UIScreen mainScreen] bounds].size.width);
    PulloutView *pulloutMenu = self.scorePulloutView;
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[sideMenuView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(sideMenuView)]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"[sideMenuView(width)][pulloutMenu]" options:0 metrics:NSDictionaryOfVariableBindings(width) views:NSDictionaryOfVariableBindings(sideMenuView, pulloutMenu)]];
    
    [self.view layoutIfNeeded];
    
    self.sideMenuStartX = sideMenuView.frame.origin.x;
    
    self.manager.leaderboardDelegate = self.sideMenu;
    
    self.isSideMenuOnScreen = NO;
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Setup pullout view layers
    [self.scorePulloutView setupLayers];
    
    // Take screenshot of main UI for use in animation
    if(self.questionTextView.text.length == 0 && self.answerLabel.text.length == 0 && self.timeLabel.text.length == 0)
    {
        self.backgroundImageView.image = [self.contentView imageSnapshot];
    }
    
    self.pulloutStartX = self.scorePulloutView.frame.origin.x;
}

#pragma mark - Connection Manager Delegate Methods
- (void) connectionManager:(ProtobowlConnectionManager *)manager didConnectWithSuccess:(BOOL)success
{
    if(success)
    {
//        LOG(@"Connected to server");
    }
    else
    {
//        LOG(@"Failed to connect to server");
    }
}

- (void) connectionManager:(ProtobowlConnectionManager *)manager didUpdateChatLines:(NSArray *)lines;
{   
    /*[self.textViewLog setLineArray:lines];
    
    CGSize textViewLogSize = [self.textViewLog.text sizeWithFont:self.textViewLog.font constrainedToSize:CGSizeMake(self.textViewLog.frame.size.width, 10000)];
    self.textViewLogHeightConstraint.constant = textViewLogSize.height + 30;*/
}

- (void) connectionManager:(ProtobowlConnectionManager *)manager didUpdateBuzzLines:(NSArray *)lines
{
    [self.textViewLog setLineArray:lines];
}

- (void) connectionManager:(ProtobowlConnectionManager *)manager didUpdateQuestion:(ProtobowlQuestion *)question
{
    // Calculate best font size
    float maxHeight = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone ? 280 : 400;
    int size = 80;
    float newHeight = 0;
    UIFont *newFont = nil;
    while((newHeight = [question.questionText sizeWithFont:(newFont = [UIFont fontWithName:@"HelveticaNeue" size:size--]) constrainedToSize:CGSizeMake(self.questionTextView.frame.size.width - 8, 10000)].height + 30) >= maxHeight);
    
    
    NSLog(@"Size: %f", newFont.pointSize);
    
    self.questionTextView.font = newFont;
    self.questionContainerHeightConstraint.constant = newHeight;
    
    [UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        [self.contentView layoutSubviews];
    } completion:nil];
    self.isNextAnimationEnabled = NO;
    self.isAnimating = NO;

    
    // Set the category
    self.answerLabel.text = question.category;
}

- (void) connectionManager:(ProtobowlConnectionManager *)manager didUpdateQuestionDisplayText:(NSString *)text
{
    self.questionTextView.text = text;
    
    CGSize constraintSize = CGSizeMake(self.questionTextView.frame.size.width, 10000);
    CGSize targetSize = [text sizeWithFont:self.questionTextView.font constrainedToSize:constraintSize lineBreakMode:NSLineBreakByWordWrapping];
    self.questionTextHeightConstraint.constant = targetSize.height;
    [self.questionContainerView setNeedsLayout];
}

- (void) connectionManager:(ProtobowlConnectionManager *)manager didUpdateTime:(float)remainingTime progress:(float)progress
{
    NSString *timeText = [NSString stringWithFormat:@"%.1f", remainingTime];
    self.timeLabel.text = timeText;
    
    [self.timeBar setProgress:progress animated:NO];
}


- (void) connectionManager:(ProtobowlConnectionManager *)manager didSetBuzzEnabled:(BOOL)isBuzzEnabled
{
    self.buzzButton.enabled = isBuzzEnabled;
    self.buzzButton.userInteractionEnabled = isBuzzEnabled;
}

- (void) connectionManager:(ProtobowlConnectionManager *)manager didEndQuestion:(ProtobowlQuestion *)question
{
    self.isNextAnimationEnabled = YES;
    
    NSString *answerWithRemovedComments = question.answerText;
    int leftBracketIndex = [answerWithRemovedComments rangeOfString:@"["].location;
    if(leftBracketIndex != NSNotFound)
    {
        answerWithRemovedComments = [answerWithRemovedComments substringToIndex:leftBracketIndex];
    }
    
    int leftParenIndex = [answerWithRemovedComments rangeOfString:@"("].location;
    if(leftParenIndex != NSNotFound)
    {
        answerWithRemovedComments = [answerWithRemovedComments substringToIndex:leftParenIndex];
    }
    
    answerWithRemovedComments = [answerWithRemovedComments stringByReplacingOccurrencesOfString:@"{" withString:@""];
    answerWithRemovedComments = [answerWithRemovedComments stringByReplacingOccurrencesOfString:@"}" withString:@""];
    
    answerWithRemovedComments = [answerWithRemovedComments stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" "]];


    self.answerLabel.text = answerWithRemovedComments;
}

- (void) connectionManager:(ProtobowlConnectionManager *)manager didUpdateUsers:(NSArray *)users
{
    // Don't care about other people's scores, but use this opportunity to update our own score
    self.myInfoLabel.text = [NSString stringWithFormat:@"%@: #%d", self.manager.myName, self.manager.myRank];
    self.myScoreLabel.text = [NSString stringWithFormat:@"%d", self.manager.myScore];
    
    [self.scorePulloutView layoutIfNeeded];
}


- (IBAction)buzzPressed:(id)sender
{
    [self.manager buzz];
    
    [self presentGuessViewController];
}

- (void) presentGuessViewController
{
    GuessViewController *guessVC = [self.storyboard instantiateViewControllerWithIdentifier:@"GuessViewController"];
    guessVC.questionDisplayText = self.questionTextView.text;
    __weak MainViewController *weakSelf = self;
    guessVC.updateGuessTextCallback = ^(NSString *guessText) {
        [weakSelf.manager updateGuess:guessText];
    };
    guessVC.submitGuessCallback = ^(NSString *guess) {
        [weakSelf.manager submitGuess:guess];
    };
    guessVC.invalidBuzzCallback = ^{
        [weakSelf.manager unpauseQuestion];
        [self dismissViewControllerAnimated:YES completion:nil];
    };
    self.manager.guessDelegate = guessVC;
    
    NSLog(@"Presenting");
    [self presentViewController:guessVC animated:YES completion:nil];
}

- (void) dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion
{
    NSLog(@"Dismissing");
    [super dismissViewControllerAnimated:flag completion:completion];
}

#define kScrollTransitionInteractionThreshold 50
#define kScrollTransitionCompletionThreshold 60
#define kScrollTransitionBackgroundImageInset 30
- (void) animateToNextQuestion
{
    if(self.isAnimating || !self.isNextAnimationEnabled || self.isSideMenuOnScreen) return;

    __weak MainViewController *weakSelf = self;
    self.isAnimating = YES;

    [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        CGRect animatedFrame = weakSelf.contentView.frame;
        animatedFrame.origin.y = -600;
        weakSelf.contentView.frame = animatedFrame;
    } completion:^(BOOL finished) {
        weakSelf.questionTextView.text = @"";
        weakSelf.answerLabel.text = @"";
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            weakSelf.backgroundImageView.frame = CGRectMake(0, 0, weakSelf.view.frame.size.width, weakSelf.view.frame.size.height);
        } completion:^(BOOL finished) {
            weakSelf.contentView.frame = CGRectMake(0, 0, weakSelf.view.frame.size.width, weakSelf.view.frame.size.height);
            weakSelf.questionContainerHeightConstraint.constant = 200;
            weakSelf.buzzButton.enabled = YES;
            weakSelf.buzzButton.userInteractionEnabled = NO;
            weakSelf.timeBar.progress = 0;
            weakSelf.backgroundImageView.frame = CGRectMake(kScrollTransitionBackgroundImageInset, kScrollTransitionBackgroundImageInset, weakSelf.view.frame.size.width - kScrollTransitionBackgroundImageInset*2, weakSelf.view.frame.size.height - kScrollTransitionBackgroundImageInset*2);
            [weakSelf.view setNeedsLayout];
            
            // Trigger next question
            [weakSelf.manager next];
        }];
    }];
}

- (void) handlePan:(UIPanGestureRecognizer *)pan
{
    if(pan.view == self.scorePulloutView)
    {
        if(pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)
        {
            float dx = self.scorePulloutView.frame.origin.x - self.pulloutStartX;
            if(dx > 180) // User has pulled enough, finish transition
            {
                [self animateSideMenuInWithDuration:0];
            }
            else // Cancel transition
            {
                [self animateSideMenuOutWithDuration:0];
            }
        }
        else
        {
            float dx = [pan translationInView:self.scorePulloutView].x;
            
            // Update pullout frame
            CGRect frame = self.scorePulloutView.frame;
            frame.origin.x += dx;
            self.scorePulloutView.frame = frame;
            
            // Update side menu frame
            frame = self.sideMenu.view.frame;
            frame.origin.x += dx;
            self.sideMenu.view.frame = frame;
        }
        [pan setTranslation:CGPointZero inView:self.scorePulloutView];
    }
    else // Handle callback from pan in Side Menu
    {
        float dx = self.sideMenu.view.frame.origin.x;
        if(pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)
        {
            if(dx < -120) // User has pulled enough, finish transition
            {
                [self animateSideMenuOutWithDuration:0];
            }
            else // Cancel transition
            {
                [self animateSideMenuInWithDuration:0];
            }
        }
        else if(pan.state == UIGestureRecognizerStateBegan)
        {
            [self.sideMenu setFullyOnscreen:NO];
        }
        else
        {
            float dx = [pan translationInView:self.sideMenu.view].x;
            
            // Update pullout frame
            CGRect frame = self.scorePulloutView.frame;
            frame.origin.x += dx * 1.5;
            self.scorePulloutView.frame = frame;
            
            // Update side menu frame
            frame = self.sideMenu.view.frame;
            frame.origin.x += dx;
            self.sideMenu.view.frame = frame;
        }
        
        [pan setTranslation:CGPointZero inView:self.sideMenu.view];
    }
}

- (void) tap:(UITapGestureRecognizer *)tap
{
    [self animateSideMenuInWithDuration:0.6];
}

- (void) animateSideMenuInWithDuration:(float) duration
{
    if(duration == 0) duration = 0.2;
    
    self.isSideMenuOnScreen = YES;
    
    float endX = [UIScreen mainScreen].bounds.size.width;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        CGRect frame = self.scorePulloutView.frame;
        frame.origin.x = endX;
        self.scorePulloutView.frame = frame;
        
        frame = self.sideMenu.view.frame;
        frame.origin.x = 0;
        self.sideMenu.view.frame = frame;
    } completion:^(BOOL complete){
        [self.sideMenu setFullyOnscreen:YES];
    }];
}

- (void) animateSideMenuOutWithDuration:(float) duration
{
    if(duration == 0) duration = 0.2;
    
    [self.sideMenu setFullyOnscreen:NO];
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        CGRect frame = self.scorePulloutView.frame;
        frame.origin.x = self.pulloutStartX;
        self.scorePulloutView.frame = frame;
        
        frame = self.sideMenu.view.frame;
        frame.origin.x = self.sideMenuStartX;
        self.sideMenu.view.frame = frame;
    } completion:^(BOOL complete){
        [self.contentView setNeedsLayout];
        self.isSideMenuOnScreen = NO;
    }];
}


#pragma mark - Interface Helper Methods
- (void) logToTextView:(NSString *)message
{
    [self.textViewLog addLine:message];
}

@end