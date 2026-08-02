# Face Digital Image Speckle Correlation (DISC) Application
**Non-Invasive, Accessible Tool to Detect Acoustic Neuroma**

**Presenter(s):** Corey Zhang, Leah Song, Jerry Gu, Shreyaa Sanjay, Zihan Jia, Eugene Jiang, Brooklyn Ratel, Divleen Singh, Shi Fu, Huiting Luo, Miriam Rafailovich, Gurtej Singh  
**Institutions:** Eastlake High School, Maclay School, Princeton International School of Mathematics and Science, West Windsor-Plainsboro High School North, The Experimental High School Attached to Beijing Normal University, Stony Brook University, The State University of New York  

---

## Overview

The **DISC (Digital Image Speckle Correlation) Application** is an iOS tool designed to assist in the early detection of **acoustic neuroma**, a benign tumor on the vestibulocochlear nerve that often results in hearing loss and facial asymmetry. Traditional diagnostic methods such as EEG are costly, inaccessible, and uncomfortable. DISC provides a **non-invasive, accessible, and affordable solution** for early diagnosis by mapping facial muscle movements through advanced image processing.

---

## Key Features

- **Face Detection & Segmentation:** Real-time facial detection using **Swift** and **CoreML** to guide accurate photo capture.  
- **Standardized Photo Capture:** Ensures consistent patient positioning to improve diagnostic accuracy.  
- **Image Processing & Speckle Correlation:** Uses **Python** and **OpenCV** to preprocess images, detect edges, contours, and regions of interest.  
- **Heatmap Generation:** Visualizes facial asymmetry by highlighting vector displacements in facial muscle movement.  
- **Grayscale Conversion & Downscaling:** Converts images to 10x10 grayscale for efficient analysis.  
- **Cross-Platform Integration:** Combines Python/OpenCV with Swift/CoreML for seamless iOS deployment.  
- **Cloud Deployment:** Uses **Azure** to integrate OpenCV into Xcode and manage GUI elements for scalability and reliability.  

---

## How It Works

1. The user positions their face in the frame guided by the app.  
2. The app captures the first reference photo and generates a **person mask**.  
3. A second photo is captured, and facial muscle displacements are calculated using **speckle correlation**.  
4. Heatmaps are generated to highlight areas of asymmetry, indicating potential acoustic neuroma.  
5. Results can guide medical consultation for early diagnosis.  

---

## Technologies Used

- **iOS Development:** Swift, UIKit, CoreML  
- **Image Processing:** Python, OpenCV, Jupyter Notebook  
- **Segmentation & Face Detection:** Vision framework, VNGeneratePersonSegmentationRequest, VNDetectFaceLandmarksRequest  
- **Cloud Integration:** Azure for scaling OpenCV integration  
- **Data Analysis:** Grayscale conversion, downscaling, bilinear interpolation for displacement calculation  

---

## Results

- Successfully identifies facial asymmetry by tracking vector displacement in facial muscles.  
- Heatmaps highlight variations in movement for features like smirks or raised eyebrows.  
- Preliminary testing on project members shows reliable detection of facial asymmetry.  
- Provides a user-friendly, time-efficient, and accurate diagnostic tool for early-stage acoustic neuroma detection.  

---

## Getting Started

1. Clone the repository:  
```bash
git clone https://github.com/yourusername/DISC-Application.git
