# 🎯 Interview Prep System

A complete **Flutter-based live interview preparation system** powered by **LiveKit** for real-time video, **Cerebras AI** for intelligent interview questions, and **Docker** for seamless deployment.

---
## 🚀 Features

- 🎥 **Real-time Video Interviews** using [LiveKit](https://livekit.io)  
- 🤖 **AI-Powered Interview Agent** using [Cerebras LLM](https://cerebras.ai)  
- 📄 **Resume Upload & Analysis**  
- ❓ **Dynamic Question Generation** based on role and requirements  
- 💬 **Real-time Feedback** during the interview  

---

## 🛠️ Setup Instructions

### 1. Clone the Repository
```bash
git clone <your-repo>
cd interview-prep
```

### 2. Backend Setup

#### Install Dependencies
```bash
cd interview-backend
npm install
```

#### Configure Environment Variables
```bash
cp .env.example .env
```

Edit `.env` and add your credentials:
```env
LIVEKIT_API_KEY=your-livekit-api-key
LIVEKIT_API_SECRET=your-livekit-api-secret
LIVEKIT_URL=wss://your-livekit-server.livekit.cloud
CEREBRAS_API_KEY=your-cerebras-api-key
```

Get Your Keys:
- **LiveKit** → https://cloud.livekit.io
- **Cerebras** → https://cerebras.ai

#### Run Backend (Development)
```bash
npm run dev
```

#### Run Backend (Production with Docker)
```bash
docker-compose up -d
```

### 3. Flutter App Setup

#### Install Dependencies
```bash
cd interview
flutter pub get
```

#### Run Flutter App
```bash
flutter run
```
