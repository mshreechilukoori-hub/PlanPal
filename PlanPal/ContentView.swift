// Project: PlanPal
// EID: mc77599
// Course: CS 329E

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import UserNotifications

struct Course: Identifiable {
    let id = UUID()
    var courseNumber: String
    var title: String
    var difficulty: Int
    var priority: Int
    var weeklyTargetHours: Int
}

struct StudyBlock: Identifiable {
    let id = UUID()
    var day: String
    var time: String
    var courseNumber: String
    var type: String
}

struct PeerMatch: Identifiable {
    let id = UUID()
    var requestId: String = ""
    var userId: String
    var name: String
    var courseNumber: String
    var matchPercent: Int
    var sharedSessions: [StudyBlock] = []
}

class PlanPalData: ObservableObject {
    @Published var isLoggedIn = false
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var major = ""
    @Published var weeklyGoal = 10
    @Published var darkMode = false
    @Published var notificationsOn = false
    @Published var profileImageData: Data? = nil
    
    let db = Firestore.firestore()
    
    func loadConnectedUserIds(completion: @escaping (Set<String>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion([])
            return
        }

        db.collection("matchRequests").getDocuments { snapshot, error in
            if let error = error {
                completion([])
                return
            }

            var connectedIds = Set<String>()

            snapshot?.documents.forEach { doc in
                let data = doc.data()
                let fromUserId = data["fromUserId"] as? String ?? ""
                let toUserId = data["toUserId"] as? String ?? ""
                let status = data["status"] as? String ?? ""

                if status == "pending" || status == "accepted" {
                    if fromUserId == currentUser.uid {
                        connectedIds.insert(toUserId)
                    } else if toUserId == currentUser.uid {
                        connectedIds.insert(fromUserId)
                    }
                }
            }
            completion(connectedIds)
        }
    }
    
    func deletePeerSessions(with match: PeerMatch) {
        guard let currentUser = Auth.auth().currentUser else { return }

        db.collection("peerSessions").getDocuments { snapshot, error in
            if let error = error {
                return
            }

            snapshot?.documents.forEach { doc in
                let data = doc.data()
                let fromUserId = data["fromUserId"] as? String ?? ""
                let toUserId = data["toUserId"] as? String ?? ""

                let isBetweenUsers =
                    (fromUserId == currentUser.uid && toUserId == match.userId) ||
                    (fromUserId == match.userId && toUserId == currentUser.uid)

                if isBetweenUsers {
                    doc.reference.delete()
                }
            }
        }
    }
    
    func savePeerSession(with match: PeerMatch, session: StudyBlock) {
        guard let currentUser = Auth.auth().currentUser else { return }

        db.collection("peerSessions").addDocument(data: [
            "fromUserId": currentUser.uid,
            "toUserId": match.userId,
            "courseNumber": session.courseNumber,
            "day": session.day,
            "time": session.time,
            "type": session.type
        ])
    }

    func loadPeerSessions(completion: (() -> Void)? = nil) {
        guard let currentUser = Auth.auth().currentUser else { return }

        db.collection("peerSessions").getDocuments { snapshot, error in
            if let error = error {
                return
            }

            var loadedSessions: [StudyBlock] = []

            snapshot?.documents.forEach { doc in
                let data = doc.data()
                let fromUserId = data["fromUserId"] as? String ?? ""
                let toUserId = data["toUserId"] as? String ?? ""

                if fromUserId == currentUser.uid || toUserId == currentUser.uid {
                    loadedSessions.append(
                        StudyBlock(
                            day: data["day"] as? String ?? "",
                            time: data["time"] as? String ?? "",
                            courseNumber: data["courseNumber"] as? String ?? "",
                            type: data["type"] as? String ?? "Peer Session"
                        )
                    )
                }
            }
            DispatchQueue.main.async {
                self.manualSessions = loadedSessions
                completion?()
            }
        }
    }
    
    func unmatchUser(_ match: PeerMatch) {
        guard !match.requestId.isEmpty else { return }

        db.collection("matchRequests").document(match.requestId).delete { error in
            if let error = error {
                print("Unmatch error: \(error.localizedDescription)")
            } else {
                self.sendLocalNotification(
                    title: "Match Removed",
                    body: "You are no longer matched with \(match.name)."
                )
            }
        }
    }
    
    func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    func loadAcceptedMatches(completion: @escaping ([PeerMatch]) -> Void) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        db.collection("matchRequests")
            .whereField("status", isEqualTo: "accepted")
            .getDocuments { snapshot, error in
                
                if let error = error {
                    return
                }
                
                var accepted: [PeerMatch] = []
                
                snapshot?.documents.forEach { doc in
                    let data = doc.data()
                    let matchPercent = data["matchPercent"] as? Int ?? 0
                    let fromUserId = data["fromUserId"] as? String ?? ""
                    let toUserId = data["toUserId"] as? String ?? ""
                    let fromName = data["fromName"] as? String ?? "Student"
                    let toName = data["toName"] as? String ?? "Student"
                    let course = data["courseNumber"] as? String ?? ""
                    
                    if fromUserId == currentUser.uid {
                        accepted.append(
                            PeerMatch(
                                requestId: doc.documentID,
                                userId: toUserId,
                                name: toName,
                                courseNumber: course,
                                matchPercent: matchPercent
                            )
                        )
                    } else if toUserId == currentUser.uid {
                        accepted.append(
                            PeerMatch(
                                requestId: doc.documentID,
                                userId: fromUserId,
                                name: fromName,
                                courseNumber: course,
                                matchPercent: matchPercent
                            )
                        )
                    }
                }
                
                DispatchQueue.main.async {
                    completion(accepted)
                }
            }
    }
    
    func acceptRequest(from match: PeerMatch) {
        guard !match.requestId.isEmpty else { return }

        db.collection("matchRequests").document(match.requestId).updateData([
            "status": "accepted"
        ])
    }
    
    func declineRequest(from match: PeerMatch) {
        guard !match.requestId.isEmpty else { return }

        db.collection("matchRequests").document(match.requestId).delete()
    }
    
    func calculateMatchPercent(myCourse: Course, otherCourse: Course) -> Int {
        let difficultyDifference = abs(myCourse.difficulty - otherCourse.difficulty)
        let priorityDifference = abs(myCourse.priority - otherCourse.priority)
        
        let penalty = (difficultyDifference * 5) + (priorityDifference * 5)
        let score = max(50, 100 - penalty)
        
        return score
    }
    
    func sendMatchRequest(to match: PeerMatch) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        db.collection("matchRequests").addDocument(data: [
            "fromUserId": currentUser.uid,
            "fromName": "\(firstName) \(lastName)",
            "toUserId": match.userId,
            "toName": match.name,
            "courseNumber": match.courseNumber,
            "matchPercent": match.matchPercent,
            "status": "pending"
        ])
    }
    
    func loadIncomingRequests(completion: @escaping ([PeerMatch]) -> Void) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        db.collection("matchRequests")
            .whereField("toUserId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                
                if let error = error {
                    return
                }
                
                var requests: [PeerMatch] = []
                
                snapshot?.documents.forEach { doc in
                    let data = doc.data()
                    
                    let fromName = data["fromName"] as? String ?? "Student"
                    let course = data["courseNumber"] as? String ?? ""
                    let fromUserId = data["fromUserId"] as? String ?? ""
                    
                    requests.append(
                        PeerMatch(
                            requestId: doc.documentID,
                            userId: fromUserId,
                            name: fromName,
                            courseNumber: course,
                            matchPercent: data["matchPercent"] as? Int ?? 0
                        )
                    )
                }
                
                DispatchQueue.main.async {
                    completion(requests)
                }
            }
    }
    
    func saveCurrentUserToFirestore() {
        guard let user = Auth.auth().currentUser else { return }
        
        let coursesData = courses.map { course in
            [
                "courseNumber": course.courseNumber.uppercased(),
                "title": course.title,
                "difficulty": course.difficulty,
                "priority": course.priority,
                "weeklyTargetHours": course.weeklyTargetHours
            ] as [String : Any]
        }
        
        db.collection("users").document(user.uid).setData([
            "firstName": firstName,
            "lastName": lastName,
            "major": major,
            "weeklyGoal": weeklyGoal,
            "email": user.email ?? "",
            "courses": coursesData
        ], merge: true)
    }

    func loadCurrentUserFromFirestore(completion: (() -> Void)? = nil) {
        guard let user = Auth.auth().currentUser else { return }
        
        db.collection("users").document(user.uid).getDocument { document, error in
            if let error = error {
                completion?()
                return
            }
            
            guard let info = document?.data() else {
                DispatchQueue.main.async {
                    self.firstName = ""
                    self.lastName = ""
                    self.major = ""
                    self.weeklyGoal = 10
                    self.courses = []
                    self.manualSessions = []
                    self.matches = []
                    completion?()
                }
                return
            }
            
            let firstName = info["firstName"] as? String ?? ""
            let lastName = info["lastName"] as? String ?? ""
            let major = info["major"] as? String ?? ""
            let weeklyGoal = info["weeklyGoal"] as? Int ?? 10
            
            var loadedCourses: [Course] = []
            
            if let courseDictionaries = info["courses"] as? [[String: Any]] {
                loadedCourses = courseDictionaries.map { dict in
                    Course(
                        courseNumber: dict["courseNumber"] as? String ?? "",
                        title: dict["title"] as? String ?? "",
                        difficulty: dict["difficulty"] as? Int ?? 5,
                        priority: dict["priority"] as? Int ?? 5,
                        weeklyTargetHours: dict["weeklyTargetHours"] as? Int ?? 3
                    )
                }
            } else if let oldCourseNumbers = info["courses"] as? [String] {
                loadedCourses = oldCourseNumbers.map {
                    Course(courseNumber: $0, title: "", difficulty: 5, priority: 5, weeklyTargetHours: 3)
                }
            }
            
            DispatchQueue.main.async {
                self.firstName = firstName
                self.lastName = lastName
                self.major = major
                self.weeklyGoal = weeklyGoal
                self.courses = loadedCourses
                self.manualSessions = []
                completion?()
            }
        }
    }

    func loadMatchesFromFirestore() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        loadConnectedUserIds { connectedIds in
            self.db.collection("users").getDocuments { snapshot, error in
                if let error = error {
                    return
                }
                
                var newMatches: [PeerMatch] = []
                
                snapshot?.documents.forEach { doc in
                    if doc.documentID == currentUser.uid { return }
                    if connectedIds.contains(doc.documentID) { return }
                    
                    let info = doc.data()
                    let firstName = info["firstName"] as? String ?? "Student"
                    let lastName = info["lastName"] as? String ?? ""
                    
                    guard let otherCoursesData = info["courses"] as? [[String: Any]] else {
                        return
                    }
                    
                    let otherCourses = otherCoursesData.map { dict in
                        Course(
                            courseNumber: dict["courseNumber"] as? String ?? "",
                            title: dict["title"] as? String ?? "",
                            difficulty: dict["difficulty"] as? Int ?? 5,
                            priority: dict["priority"] as? Int ?? 5,
                            weeklyTargetHours: dict["weeklyTargetHours"] as? Int ?? 3
                        )
                    }
                    
                    for myCourse in self.courses {
                        if let matchingOtherCourse = otherCourses.first(where: {
                            $0.courseNumber.uppercased() == myCourse.courseNumber.uppercased()
                        }) {
                            let percent = self.calculateMatchPercent(
                                myCourse: myCourse,
                                otherCourse: matchingOtherCourse
                            )
                            
                            newMatches.append(
                                PeerMatch(
                                    userId: doc.documentID,
                                    name: "\(firstName) \(lastName)",
                                    courseNumber: myCourse.courseNumber.uppercased(),
                                    matchPercent: percent
                                )
                            )
                            
                            break
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.matches = newMatches.sorted { $0.matchPercent > $1.matchPercent }
                }
            }
        }
    }
    
    @Published var courses: [Course] = []
    @Published var manualSessions: [StudyBlock] = []
    @Published var matches: [PeerMatch] = []
    
    func generateTimes() -> [String] {
        var result: [String] = []
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        let calendar = Calendar.current
        
        for hour in 10...22 {
            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) {
                result.append(formatter.string(from: date))
            }
        }
        
        return result
    }
    
    var generatedStudyPlan: [StudyBlock] {
        var blocks: [StudyBlock] = []
        
        let sortedCourses = courses.sorted {
            ($0.priority + $0.difficulty) > ($1.priority + $1.difficulty)
        }
        
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let times = generateTimes()
        
        var blockIndex = 0
        
        for course in sortedCourses {
            let numberOfBlocks = course.weeklyTargetHours
            
            for _ in 0..<numberOfBlocks {
                blocks.append(
                    StudyBlock(
                        day: days[blockIndex % days.count],
                        time: times[blockIndex % times.count],
                        courseNumber: course.courseNumber,
                        type: "Auto Study Block"
                    )
                )
                blockIndex += 1
            }
        }
        
        return blocks + manualSessions
    }
    
    func hasOverlap(day: String, time: String) -> Bool {
        generatedStudyPlan.contains { $0.day == day && $0.time == time }
    }
    
    func deleteAccount() {
        firstName = ""
        lastName = ""
        major = ""
        weeklyGoal = 0
        courses.removeAll()
        manualSessions.removeAll()
        matches.removeAll()
        isLoggedIn = false
    }
}

struct ContentView: View {
    @StateObject private var data = PlanPalData()
    
    var body: some View {
        Group {
            if data.isLoggedIn {
                MainTabView()
                    .environmentObject(data)
                    .preferredColorScheme(data.darkMode ? .dark : .light)
            } else {
                LoginView()
                    .environmentObject(data)
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var data: PlanPalData
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.yellow.opacity(0.18).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image("planpal_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                    
                    Text("PlanPal")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("Plan Smarter, Study Better")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                    
                    Button("Log In") {
                        Auth.auth().signIn(withEmail: email, password: password) { result, error in
                            if let error = error {
                                let message = error.localizedDescription.lowercased()
                                
                                if message.contains("no user") ||
                                    message.contains("user") ||
                                    message.contains("credential") ||
                                    message.contains("malformed") {
                                    errorMessage = "No account found with this email, or the login information is incorrect."
                                } else if message.contains("password") {
                                    errorMessage = "Incorrect password. Please try again."
                                } else {
                                    errorMessage = "Login failed. Please check your email and password."
                                }
                                
                                showError = true
                            } else {
                                data.loadCurrentUserFromFirestore {
                                    data.loadMatchesFromFirestore()
                                    data.isLoggedIn = true
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Register for an Account") {
                        showRegister = true
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
                    .environmentObject(data)
            }
        }
        .alert("Login Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
    }
}

struct RegisterView: View {
    @EnvironmentObject var data: PlanPalData
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var major = ""
    
    var body: some View {
        Form {
            Section("Create Your Profile") {
                TextField("First Name", text: $firstName)
                TextField("Last Name", text: $lastName)
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                SecureField("Re-enter Password", text: $confirmPassword)
                TextField("Major", text: $major)
            }
            
            Section {
                Button("Continue") {
                    guard password == confirmPassword else {
                        return
                    }
                    Auth.auth().createUser(withEmail: email, password: password) { result, error in
                        if let error = error {
                            print(error.localizedDescription)
                        } else {
                            data.firstName = firstName
                            data.lastName = lastName
                            data.major = major
                            
                            data.courses.removeAll()
                            data.manualSessions.removeAll()
                            data.matches.removeAll()
                            
                            data.saveCurrentUserToFirestore()
                            data.isLoggedIn = true
                        }
                    }
                }
            }
        }
        .navigationTitle("Register")
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            WeeklyPlanView()
                .tabItem {
                    Label("Weekly", systemImage: "calendar")
                }
            
            CoursesView()
                .tabItem {
                    Label("Courses", systemImage: "book")
                }
            
            MatchesView()
                .tabItem {
                    Label("Matches", systemImage: "person.2")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}

struct WeeklyPlanView: View {
    @EnvironmentObject var data: PlanPalData
    
    var autoBlocks: [StudyBlock] {
        data.generatedStudyPlan.filter { $0.type == "Auto Study Block" }
    }
    
    var peerSessions: [StudyBlock] {
        data.manualSessions
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("This Week") {
                    ForEach(autoBlocks) { block in
                        studyBlockCard(block)
                    }
                }
                
                Section("Peer Sessions") {
                    if peerSessions.isEmpty {
                        Text("No peer sessions booked yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(peerSessions) { block in
                            studyBlockCard(block)
                        }
                        .onDelete { indexSet in
                            data.manualSessions.remove(atOffsets: indexSet)
                        }
                    }
                }
                
                Section("Progress") {
                    Text("Total Planned Blocks: \(autoBlocks.count + peerSessions.count)")
                    Text("Weekly Goal: \(data.weeklyGoal) hours")
                    
                    if autoBlocks.count + peerSessions.count < data.weeklyGoal {
                        Text("You are behind your weekly target. Consider adding another study session.")
                            .foregroundColor(.orange)
                    } else {
                        Text("Great job! You are on track with your weekly goal.")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("My Study Plan")
            .onAppear {
                data.loadPeerSessions()
            }
        }
    }
    
    func studyBlockCard(_ block: StudyBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.courseNumber)
                .font(.headline)
            
            Text("\(block.day) at \(block.time)")
            
            Text(block.type)
                .font(.caption)
                .foregroundColor(block.type == "Peer Session" ? .blue : .gray)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.vertical, 4)
    }
}

struct CoursesView: View {
    @EnvironmentObject var data: PlanPalData
    @State private var showAddCourse = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(data.courses) { course in
                    NavigationLink {
                        if let index = data.courses.firstIndex(where: { $0.id == course.id }) {
                            CourseDetailView(course: $data.courses[index])
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(course.courseNumber)
                                .font(.headline)
                            Text(course.title)
                                .foregroundColor(.secondary)
                            Text("Difficulty: \(course.difficulty)/10 • Priority: \(course.priority)/10 • Target: \(course.weeklyTargetHours) hrs")
                                .font(.caption)
                        }
                    }
                }
                .onDelete { indexSet in
                    data.courses.remove(atOffsets: indexSet)
                    data.saveCurrentUserToFirestore()
                    data.loadMatchesFromFirestore()
                }
            }
            .navigationTitle("My Courses")
            .toolbar {
                Button {
                    showAddCourse = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showAddCourse) {
                AddCourseView()
                    .environmentObject(data)
            }
        }
    }
}

struct AddCourseView: View {
    @EnvironmentObject var data: PlanPalData
    @Environment(\.dismiss) var dismiss
    
    @State private var courseNumber = ""
    @State private var title = ""
    @State private var difficulty = 5.0
    @State private var priority = 5.0
    @State private var weeklyHours = 3.0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Course Info") {
                    TextField("Course Number, ex: ECO 304K", text: $courseNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("Course Title", text: $title)
                }
                
                Section("Study Settings") {
                    Slider(value: $difficulty, in: 1...10, step: 1)
                    Text("Difficulty: \(Int(difficulty))/10")
                    
                    Slider(value: $priority, in: 1...10, step: 1)
                    Text("Priority: \(Int(priority))/10")
                    
                    Stepper("Weekly Target: \(Int(weeklyHours)) hrs", value: $weeklyHours, in: 1...20)
                }
            }
            .navigationTitle("Add Course")
            .toolbar {
                Button("Save") {
                    let newCourse = Course(
                        courseNumber: courseNumber.uppercased(),
                        title: title,
                        difficulty: Int(difficulty),
                        priority: Int(priority),
                        weeklyTargetHours: Int(weeklyHours)
                    )
                    data.courses.append(newCourse)
                    data.saveCurrentUserToFirestore()
                    data.loadMatchesFromFirestore()
                    dismiss()
                }
            }
        }
    }
}

struct CourseDetailView: View {
    @EnvironmentObject var data: PlanPalData
    @Environment(\.dismiss) var dismiss
    
    @Binding var course: Course
    @State private var showDeleteAlert = false
    
    var body: some View {
        Form {
            Section("Course Info") {
                TextField("Course Number", text: $course.courseNumber)
                    .textInputAutocapitalization(.characters)
                TextField("Course Title", text: $course.title)
            }
            
            Section("Course Settings") {
                Slider(
                    value: Binding(
                        get: { Double(course.difficulty) },
                        set: { course.difficulty = Int($0) }
                    ),
                    in: 1...10,
                    step: 1
                )
                Text("Difficulty: \(course.difficulty)/10")
                
                Slider(
                    value: Binding(
                        get: { Double(course.priority) },
                        set: { course.priority = Int($0) }
                    ),
                    in: 1...10,
                    step: 1
                )
                Text("Priority: \(course.priority)/10")
                
                Stepper("Weekly Target: \(course.weeklyTargetHours) hrs", value: $course.weeklyTargetHours, in: 1...20)
            }
            
            Section("Analytics") {
                Text("Focus Score: \(course.difficulty + course.priority)/20")
                Text("Weekly Target: \(course.weeklyTargetHours) hours")
                
                ProgressView(
                    value: Double(course.difficulty + course.priority),
                    total: 20
                ) {
                    Text("Recommended Focus Level")
                }
            }
            
            Section("Matching Note") {
                Text("PlanPal uses course numbers to reduce matching issues caused by typos or capitalization differences.")
                    .font(.caption)
            }
            
            Section {
                Button("Delete Course", role: .destructive) {
                    showDeleteAlert = true
                }
            }
        }
        .navigationTitle(course.courseNumber)
        .onDisappear {
            data.saveCurrentUserToFirestore()
            data.loadMatchesFromFirestore()
        }
        .alert("Delete Course?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                data.courses.removeAll { $0.id == course.id }
                data.saveCurrentUserToFirestore()
                data.loadMatchesFromFirestore()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the course from your course list and weekly study plan.")
        }
    }
}

struct MatchesView: View {
    @EnvironmentObject var data: PlanPalData
    
    @State private var incomingRequests: [PeerMatch] = []
    @State private var acceptedMatches: [PeerMatch] = []
    @State private var selectedTab = "Suggested"
    @State private var selectedMatch: PeerMatch?
    @State private var showMatchRemovedAlert = false
    
    let tabs = ["Suggested", "Requests", "My Matches"]
    
    var body: some View {
        NavigationStack {
            VStack {
                Picker("Match Type", selection: $selectedTab) {
                    ForEach(tabs, id: \.self) { tab in
                        Text(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                List {
                    if selectedTab == "Suggested" {
                        Section("Suggested Study Partners") {
                            if data.matches.isEmpty {
                                Text("No suggested matches yet.")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(data.matches) { match in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(match.name)
                                                    .font(.headline)
                                                Text("Shared Course: \(match.courseNumber)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Text("\(match.matchPercent)%")
                                                .bold()
                                                .foregroundColor(.green)
                                        }
                                        
                                        Button("Send Match Request") {
                                            data.sendMatchRequest(to: match)
                                            data.matches.removeAll { $0.id == match.id }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    } else if selectedTab == "Requests" {
                        Section("Incoming Requests") {
                            if incomingRequests.isEmpty {
                                Text("No incoming requests.")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(incomingRequests) { match in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(match.name)
                                            .font(.headline)
                                        
                                        Text("Shared Course: \(match.courseNumber)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text("Request pending")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        
                                        HStack {
                                            Button("Accept") {
                                                data.acceptRequest(from: match)
                                                incomingRequests.removeAll { $0.id == match.id }
                                                data.matches.removeAll { $0.userId == match.userId }

                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                    data.loadAcceptedMatches { matches in
                                                        self.acceptedMatches = matches
                                                    }
                                                    selectedTab = "My Matches"
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            
                                            Button("Decline", role: .destructive) {
                                                data.declineRequest(from: match)
                                                incomingRequests.removeAll { $0.id == match.id }
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    } else {
                        Section("My Matches") {
                            if acceptedMatches.isEmpty {
                                Text("No accepted matches yet.")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(acceptedMatches) { match in
                                    Button {
                                        selectedMatch = match
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(match.name)
                                                .font(.headline)
                                            Text("Shared Course: \(match.courseNumber)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("Tap to schedule a study session")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Matches")
            .alert("Match Removed", isPresented: $showMatchRemovedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("One of your matches has been removed.")
            }
            .onAppear {
                data.loadMatchesFromFirestore()
                
                data.loadIncomingRequests { requests in
                    self.incomingRequests = requests
                }
                
                data.loadAcceptedMatches { matches in
                    if !self.acceptedMatches.isEmpty && matches.count < self.acceptedMatches.count {
                        self.showMatchRemovedAlert = true
                    }
                    
                    self.acceptedMatches = matches
                }
            }
            .sheet(item: $selectedMatch, onDismiss: {
                data.loadAcceptedMatches { matches in
                    self.acceptedMatches = matches
                }
                data.loadMatchesFromFirestore()
            }) { match in
                MatchDetailView(match: match)
                    .environmentObject(data)
            }
        }
    }
}

struct MatchDetailView: View {
    @EnvironmentObject var data: PlanPalData
    @Environment(\.dismiss) var dismiss
    
    let match: PeerMatch
    
    @State private var selectedDay = "Monday"
    @State private var selectedTime = "10:00 AM"
    @State private var showOverlapAlert = false
    @State private var showUnmatchAlert = false
    
    let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
    var times: [String] {
        data.generateTimes()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Match Details") {
                    Text(match.name)
                    Text("\(match.matchPercent)% Match")
                    Text("Shared Course: \(match.courseNumber)")
                }
                
                Section("Book Session") {
                    Picker("Day", selection: $selectedDay) {
                        ForEach(days, id: \.self) { day in
                            Text(day)
                        }
                    }
                    
                    Picker("Time", selection: $selectedTime) {
                        ForEach(times, id: \.self) { time in
                            Text(time)
                        }
                    }
                    
                    Button("Book Session") {
                        if data.hasOverlap(day: selectedDay, time: selectedTime) {
                            showOverlapAlert = true
                        } else {
                            bookSession()
                        }
                    }
                }
                
                Section {
                    Button("Unmatch", role: .destructive) {
                        showUnmatchAlert = true
                    }
                }
            }
            .navigationTitle(match.name)
            .alert("Time Conflict", isPresented: $showOverlapAlert) {
                Button("Replace with Peer Session") {
                    data.manualSessions.removeAll {
                        $0.day == selectedDay && $0.time == selectedTime
                    }
                    bookSession()
                }
                
                Button("Choose Another Time", role: .cancel) { }
            } message: {
                Text("This peer session overlaps with an automatically generated study block. You can replace it or choose another time.")
            }
            .alert("Unmatch?", isPresented: $showUnmatchAlert) {
                Button("Delete Shared Sessions", role: .destructive) {
                    data.manualSessions.removeAll {
                        $0.courseNumber == match.courseNumber && $0.type == "Peer Session"
                    }

                    data.deletePeerSessions(with: match)
                    data.unmatchUser(match)
                    dismiss()
                }

                Button("Keep Sessions") {
                    data.unmatchUser(match)
                    dismiss()
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you want to delete all shared study sessions with this match?")
            }
        }
    }
    
    func bookSession() {
        let session = StudyBlock(
            day: selectedDay,
            time: selectedTime,
            courseNumber: match.courseNumber,
            type: "Peer Session"
        )

        data.manualSessions.append(session)
        data.savePeerSession(with: match, session: session)
        dismiss()
    }
}

struct ProfileView: View {
    @EnvironmentObject var data: PlanPalData
    @State private var showEditProfile = false
    @State private var selectedPhoto: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        if let imageData = data.profileImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.gray)
                        }

                        PhotosPicker("Select Profile Photo", selection: $selectedPhoto, matching: .images)
                            .onChange(of: selectedPhoto) { oldValue, newValue in
                                Task {
                                    if let dataImage = try? await newValue?.loadTransferable(type: Data.self) {
                                        data.profileImageData = dataImage
                                    }
                                }
                            }
                        
                        Text("\(data.firstName) \(data.lastName)")
                            .font(.title2)
                            .bold()
                        
                        Text(data.major)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section("Study Goal") {
                    Stepper("Weekly Goal: \(data.weeklyGoal) hrs", value: $data.weeklyGoal, in: 1...40)
                        .onChange(of: data.weeklyGoal) { _, _ in
                            data.saveCurrentUserToFirestore()
                        }
                }
                
                Section("Settings") {
                    Toggle("Dark Mode", isOn: $data.darkMode)
                    
                    Button("Edit Profile") {
                        showEditProfile = true
                    }
                    
                    Button("Log Out") {
                        data.courses.removeAll()
                        data.manualSessions.removeAll()
                        data.matches.removeAll()
                        data.profileImageData = nil
                        data.isLoggedIn = false
                    }
                    
                    Button("Delete Profile", role: .destructive) {
                        data.deleteAccount()
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
                    .environmentObject(data)
            }
        }
    }
}

struct EditProfileView: View {
    @EnvironmentObject var data: PlanPalData
    @Environment(\.dismiss) var dismiss
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var major = ""
    @State private var weeklyGoal = 10.0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Edit Profile") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Major", text: $major)
                    Stepper("Weekly Goal: \(Int(weeklyGoal)) hrs", value: $weeklyGoal, in: 1...40)
                }
            }
            .navigationTitle("Edit Profile")
            .onAppear {
                firstName = data.firstName
                lastName = data.lastName
                major = data.major
                weeklyGoal = Double(data.weeklyGoal)
            }
            .toolbar {
                Button("Save") {
                    data.firstName = firstName
                    data.lastName = lastName
                    data.major = major
                    data.weeklyGoal = Int(weeklyGoal)
                    data.saveCurrentUserToFirestore()
                    dismiss()
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var data: PlanPalData
    
    var body: some View {
        NavigationStack {
            Form {
                Section("App Settings") {
                    Toggle("Dark Mode", isOn: $data.darkMode)
                    
                    Toggle("Notifications", isOn: $data.notificationsOn)
                        .onChange(of: data.notificationsOn) { oldValue, newValue in
                            if newValue {
                                requestNotificationPermission()
                                scheduleTestNotification()
                            }
                        }
                }
                
                Section("About") {
                    Text("Dark Mode changes the app appearance. Notifications allow PlanPal to send study reminders.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { success, error in
            if let error = error {
                print("Notification error: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "PlanPal Study Reminder"
        content.body = "Don't forget to check your weekly study plan!"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

#Preview {
    ContentView()
}
