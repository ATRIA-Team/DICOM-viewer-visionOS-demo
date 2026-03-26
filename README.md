# DICOM-viewer-visionOS-demo

A high-performance DICOM viewer for **visionOS**, built with SwiftUI and a custom-built DICOM decoding engine. This demo demonstrates how to handle medical imaging data (16-bit grayscale) in a spatial computing environment.

## 🚀 Features

- **Spatial Visualization:** View high-resolution medical slices in a native visionOS immersive interface.
- **Custom DICOM Engine:** Uses a dedicated `DICOM-Decoder` package for efficient metadata extraction and pixel processing.
- **Window/Level Adjustments:** Real-time application of medical presets (Lung, Bone, Brain, etc.) using `DCMWindowingProcessor`.
- **16-bit Support:** Full support for high-depth medical imaging data, normalized for 8-bit display.

## 🛠 Setup Instructions

Since this repository uses a custom internal package (`DICOM-Decoder`) that is ignored by Git to prevent synchronization conflicts, you must add it manually.

### 1. Clone the repository
```bash
git clone https://github.com/MicheleCoppola17/DICOM-viewer-visionOS-demo.git
cd DICOM-viewer-visionOS-demo
```

### 2. Add the DICOM-Decoder Package
The project expects the `DICOM-Decoder` source code to reside in the `Packages/` directory.

1.  Obtain the `DICOM-Decoder` folder (e.g., from the provided ZIP or the secondary repository).
2.  Move/Copy it into: `Packages/DICOM-Decoder/`
3.  Ensure the structure looks like this:
    ```text
    DemoDICOM/
    ├── DemoDICOM.xcodeproj
    └── Packages/
        └── DICOM-Decoder/
            ├── Package.swift
            └── Sources/
    ```

### 3. Open in Xcode
1.  Open `DemoDICOM.xcodeproj`.
2.  Xcode should automatically resolve the local package dependency now that the folder is present.
3.  Select a **visionOS Simulator** or a **Vision Pro** device.
4.  Build and Run (`⌘R`).

## 📂 Project Architecture

- **`DemoDICOM/`**: The main visionOS application logic.
  - `DICOMStore.swift`: Manages the loading, state, and processing of DICOM series.
  - `ContentView.swift`: The primary spatial UI.
  - `CGImage+DICOM.swift`: Utility for converting raw windowed data into displayable images.
- **`Packages/DICOM-Decoder/`**: The core engine.
  - `DCMDecoder`: Handles low-level binary parsing of DICOM files.
  - `DCMWindowingProcessor`: Performs the mathematical window/level transformations.

## ⚠️ Troubleshooting

If you see errors like `'DCMDecoder' is inaccessible` or `'applyWindowLevel' is inaccessible`:
- Ensure the `DICOM-Decoder` folder is correctly placed in `Packages/`.
- Verify that the package files are using `public` access modifiers for the classes and methods being called from the main app.

---
*Created by Michele Coppola*
