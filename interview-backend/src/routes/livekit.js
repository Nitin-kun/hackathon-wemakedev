import express from 'express';
import { AccessToken } from 'livekit-server-sdk';
import { v4 as uuidv4 } from 'uuid';
import { startInterviewAgent } from '../services/cerebras.js';

const router = express.Router();

router.post('/token', async (req, res) => {
  try {
    const { role, requirements, resumeUrl, githubUrl } = req.body;

    if (!role || !requirements || !resumeUrl) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const roomName = `interview-${uuidv4()}`;
    const participantName = 'candidate';

    // Create token
    const token = new AccessToken(
      process.env.LIVEKIT_API_KEY,
      process.env.LIVEKIT_API_SECRET,
      {
        identity: participantName,
        name: participantName,
      }
    );

    // ✅ In v2.13.3, grants are plain objects
    token.addGrant({
      room: roomName,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
    });

    // ✅ toJwt is async in v2
    const jwt = await token.toJwt();

    // Start AI agent in background
    startInterviewAgent({ roomName, role, requirements, resumeUrl, githubUrl })
      .catch(err => console.error('Failed to start agent:', err));

    res.json({
      token: jwt,
      roomUrl: process.env.LIVEKIT_URL || "",
      room: roomName,
    });
  } catch (error) {
    console.error('Error generating token:', error);

    res.status(500).json({
      error: 'Failed to generate token',
      details: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined,
    });
  }
});

export default router;
