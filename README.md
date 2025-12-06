# EasyReader

A modern iOS/macOS document reader app for PDFs and EPUBs with AI-powered analysis capabilities.

## Screenshots

![Screenshot 1](screenshots/Screenshot%202025-12-06%20at%201.39.43%20PM.png?raw=true)

![Screenshot 2](screenshots/Screenshot%202025-12-06%20at%201.39.55%20PM.png?raw=true)

## Features

### Document Management

- **PDF & EPUB Support** - Read and manage both PDF and EPUB documents
- **Document Import** - Import documents via file picker, drag & drop, or share extension
- **Duplicate Detection** - Automatically detects duplicate documents using file hashing
- **iCloud Sync** - Sync progress and documents across iCloud

### PDF Reading

- **Native PDF Rendering** - Smooth PDF viewing with PDFKit
- **Drawing Annotations** - Draw on PDFs with customizable colors and line widths
- **Undo Support** - Easily undo drawing annotations
- **Page Navigation** - Page indicator and smooth navigation

### EPUB Reading

- **Native EPUB Parsing** - Full EPUB support with chapter navigation
- **Responsive Layout** - Content adapts to screen size

### AI Analysis

- **Circle-to-Analyze** - Draw a circle around content to get AI explanations
- **Firebase AI Integration** - Powered by Google's Gemini model via Firebase
- **LaTeX Rendering** - Mathematical expressions rendered beautifully with SwiftMath
- **Markdown Support** - AI responses formatted with rich markdown
- **Persistent Analysis** - Analyses are saved and can be revisited

## Libraries Used

| Library                                                          | Purpose                                 |
| ---------------------------------------------------------------- | --------------------------------------- |
| [PinLayout](https://github.com/layoutBox/PinLayout)              | Fast, code-based UI layout              |
| [EPUBKit](https://github.com/witekbobrowski/EPUBKit)             | EPUB parsing and content extraction     |
| [Firebase iOS SDK](https://github.com/firebase/firebase-ios-sdk) | AI integration via Firebase AI (Gemini) |
| [Down](https://github.com/johnxnguyen/Down)                      | Markdown parsing and rendering          |
| [SwiftMath](https://github.com/mgriebling/SwiftMath)             | LaTeX mathematical expression rendering |
| [AEXML](https://github.com/tadija/AEXML)                         | XML parsing (EPUBKit dependency)        |
| [Zip](https://github.com/marmelroy/Zip)                          | Archive handling (EPUBKit dependency)   |

### Apple Frameworks

- **PDFKit** - Native PDF rendering and annotations
- **Core Data** - Document and analysis persistence
- **Combine** - Reactive data flow
- **CryptoKit** - File hashing for duplicate detection
- **UniformTypeIdentifiers** - Document type handling

## Requirements

- iOS/macOS 26.0

## Setup

1. Clone the repository
2. Open `EasyReader.xcodeproj` in Xcode
3. Add your `GoogleService-Info.plist` for Firebase
4. Build and run

## TODO

- [ ] **Follow-up Questions** - Add the ability to ask follow-up questions on AI analyses for deeper understanding
- [ ] **Auto-open Bottom Sheet** - Automatically open the AI analysis bottom sheet when the first text response is returned
- [ ] **Document Sorting** - Add sorting options for documents (by name, date added, date modified, etc.)
- [ ] **Inline Document Transformation** - Use AI to transform documents for mobile-friendly inline reading
- [ ] **Text-to-Speech (TTS)** - Add text-to-speech capabilities for reading documents aloud
