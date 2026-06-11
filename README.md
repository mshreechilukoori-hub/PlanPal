# PlanPal

PlanPal is a data-driven productivity and study planning iOS application designed to help college students optimize their academic performance by allowing students to schedule events and match with other students based on their focus, availability, and priority of the classes they are taking.

Using this information, PlanPal generates a personalized weekly study plan that allows students to allocate the necessary time to classes based on importance and workload.

---

# Dependencies and Requirements

- **Xcode Version:** Xcode 15+
- **Swift Version:** Swift 5
- **iOS Target:** iOS 17

## Frameworks/Packages

- Firebase Authentication
- Firebase Firestore
- Firebase Core

Firebase is already configured in the project, so there are no additional setups that need to be made besides running the app.

---

# Execution and Testing Instructions

## App Configuration

- Run the app on an iPhone simulator and iPhone 17 Pro is recommended.
- This app supports portrait mode only.

## User Setup

You can either register new accounts in the app or use these test accounts:

| User | Email | Password |
|--------|--------|--------|
| User A | usera@gmail.com | 123456 |
| User C | userc@gmail.com | 345876 |

---

# Testing Guide

## Authentication Flow

1. Register a new user account or use the test accounts to log in to the app.
2. Go to Profile to log out and log back in.
3. If you try to input the wrong email or password, it will show an error alert.

## Course Management

1. Go to Course and click the + to add a course (e.g., ECO 304K).
2. You can adjust these factors:
   - difficulty (slider)
   - priority (stepper)
   - weekly target hours
3. You can check to see if these changes have been after logging out and logging back in.
4. You can also click on the course after it has been added and click Delete to see if the course has been deleted and confirm removal.

## Study Plan Generation

1. Add courses with weekly targets.
2. Then go to the Weekly tab and make sure that there are auto-generated study blocks that correlate with the target hours and are distributed across certain days and times.

## Peer Matching System

1. Let two users have at least one shared course.
2. Go to Matches and click Suggested.
3. Make sure that for either user they have matching user(s) show up for them and a match percentage that is determined based on difficulty and priority for the course.

**Note:** For each shared course, I compared the absolute differences between the two users’ difficulty ratings and priority ratings and applied a weighted penalty to these differences. Each unit of difference reduces the score by a certain amount and the total penalty is subtracted from 100 and bounded by a minimum threshold. This allows users to receive a higher match score if they have little differences and lower score if they have more differences.

## Match Requests

1. A user can send a match request to another user.
2. That user who they requested to match can go to Requests and see their match requests.
3. Then they can either accept or decline the request.
4. If they accept the request then both users appear in My Matches for them and their Suggested no longer shows users who have already matched. If they decline the request, then their request will no longer show up in Requests for that user.

## Peer Session Scheduling

1. The user can then go to My Matches and open up their match.
2. Then they can book a peer session based on what day and time works for them.
3. After they book a session, it will then appear in Weekly in their This Week plan and it will be shown to both users and be shown even if the user logs in or closes the app.

## Unmatch Users

1. To unmatch with a user, go to My Matches and select a certain match and click Unmatch.
2. This match will then be removed for both users and the user has the option to remove the shared sessions between the user or keep it and if they click remove it will delete the peer sessions in the Weekly plan, and an in-app alert will appear for the users that have unmatched with each other.

## Settings and Profile

1. The user can go to Profile to change their name, major, and weekly goal and also include a profile image.
2. The user can also go to Settings to switch to dark mode and have notifications based on their preferences.
3. These changes are then shown across the app.

## Notifications

- There are local notifications in this app for users that have removed matches with a user.
- These notifications are device-local and no push notifications have been implemented.

---

# Feature Implementation Checklist

## Authentication (Firebase)

- Users can register and log in ✅
  - Implemented using `Auth.auth().createUser` and `Auth.auth().signIn` in RegisterView and LoginView
- Error alert for invalid credentials ✅
  - Implemented using `.alert("Login Error")` in LoginView

## Data Management (Firestore)

- User profiles are stored in Firestore ✅
- Course data is saved and shown for users ✅
- Data is shown throughout the app even after closing or logging out ✅
- Data retrieval for matches and sessions ✅
- Sync updates through Firestore ✅

## SwiftUI Components

- TabView navigation ✅
- NavigationStack based flow ✅
- Sliders (difficulty) ✅
- Steppers (priority) ✅
- Pickers (day/time selection) ✅
- Toggles (settings) ✅
- Alerts (errors and actions) ✅
- Sheets (match details and scheduling) ✅

## Course Management

- Users can add, edit, and delete courses ✅
- Course data is shown across the app after logging out or leaving the app ✅

## Study Plan Generation

- Weekly study plan is generated for users ✅
- Study blocks are based on the users weekly targets ✅

## Matching System

- Users are matched based on shared courses ✅
- Match percentage based on differences ✅
- Suggested matches for users ✅

## Match Requests

- Users can send, accept, and decline match requests ✅
- Requests are stored and retrieved from Firestore ✅

## Peer Sessions

- Users can schedule study sessions with matched users ✅
- Sessions are shared between matched users ✅

## Unmatching

- Users can unmatch and remove users ✅
- Shared session can be deleted or kept after unmatching ✅

## Notifications

- Local notifications are triggered for certain actions ✅

## Profile and Settings

- Users can edit user profile information and weekly goals ✅
- Dark mode and notification toggles ✅
- Users can select profile images to add ✅
