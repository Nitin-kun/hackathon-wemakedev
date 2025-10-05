import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import livekitRoutes from './routes/livekit.js';
import uploadRoutes from './routes/upload.js';
import agentRoutes from './routes/agent.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 7880;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes
app.use('/api', uploadRoutes);
app.use('/api/livekit', livekitRoutes);
app.use('/api/agent', agentRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📡 LiveKit URL: ${process.env.LIVEKIT_URL}`);
});