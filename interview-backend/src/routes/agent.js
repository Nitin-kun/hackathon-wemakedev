import express from 'express';
import { getAgent, removeAgent } from '../services/cerebras.js';

const router = express.Router();

// Middleware to log all requests
router.use((req, res, next) => {
  console.log('\n=== API REQUEST ===');
  console.log(`Timestamp: ${new Date().toISOString()}`);
  console.log(`Method: ${req.method}`);
  console.log(`Path: ${req.path}`);
  console.log(`Body:`, JSON.stringify(req.body, null, 2));
  console.log('==================\n');
  next();
});

router.post('/question', async (req, res) => {
  const startTime = Date.now();
  
  try {
    const { roomName } = req.body;
    
    console.log(`[/question] Fetching question for room: ${roomName}`);
    
    const agent = getAgent(roomName);

    if (!agent) {
      console.error(`[/question] Agent not found for room: ${roomName}`);
      return res.status(404).json({ error: 'Agent not found' });
    }

    console.log(`[/question] Agent found, generating question...`);
    const question = await agent.askQuestion();
    
    const duration = Date.now() - startTime;
    
    console.log('\n=== QUESTION GENERATED ===');
    console.log(`Room: ${roomName}`);
    console.log(`Duration: ${duration}ms`);
    console.log(`Question: ${question}`);
    console.log(`Question Count: ${agent.questionCount}`);
    console.log('=========================\n');
    
    res.json({ 
      question,
      questionNumber: agent.questionCount, // Hidden from UI, but logged
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    const duration = Date.now() - startTime;
    
    console.error('\n=== QUESTION ERROR ===');
    console.error(`Duration: ${duration}ms`);
    console.error(`Error:`, error.message);
    console.error(`Stack:`, error.stack);
    console.error('=====================\n');
    
    res.status(500).json({ error: 'Failed to generate question' });
  }
});

router.post('/response', async (req, res) => {
  const startTime = Date.now();
  
  try {
    const { roomName, response: candidateResponse } = req.body;
    
    console.log('\n=== CANDIDATE RESPONSE ===');
    console.log(`Room: ${roomName}`);
    console.log(`Response Length: ${candidateResponse?.length || 0} characters`);
    console.log(`Response: ${candidateResponse}`);
    console.log('========================\n');
    
    const agent = getAgent(roomName);

    if (!agent) {
      console.error(`[/response] Agent not found for room: ${roomName}`);
      return res.status(404).json({ error: 'Agent not found' });
    }

    console.log(`[/response] Processing candidate response...`);
    const feedback = await agent.provideFeedback(candidateResponse);
    
    const duration = Date.now() - startTime;
    
    console.log('\n=== FEEDBACK GENERATED ===');
    console.log(`Room: ${roomName}`);
    console.log(`Duration: ${duration}ms`);
    console.log(`Feedback: ${feedback}`);
    console.log(`Conversation Length: ${agent.conversationHistory.length} messages`);
    console.log('=========================\n');
    
    res.json({ 
      feedback,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    const duration = Date.now() - startTime;
    
    console.error('\n=== FEEDBACK ERROR ===');
    console.error(`Duration: ${duration}ms`);
    console.error(`Error:`, error.message);
    console.error(`Stack:`, error.stack);
    console.error('=====================\n');
    
    res.status(500).json({ error: 'Failed to process response' });
  }
});

router.post('/final-feedback', async (req, res) => {
  const startTime = Date.now();
  
  try {
    const { roomName, participantIdentity } = req.body;
    
    console.log('\n=== FINAL FEEDBACK REQUEST ===');
    console.log(`Room: ${roomName}`);
    console.log(`Participant: ${participantIdentity}`);
    console.log('=============================\n');
    
    const agent = getAgent(roomName);

    if (!agent) {
      console.error(`[/final-feedback] Agent not found for room: ${roomName}`);
      return res.status(404).json({ error: 'Agent not found' });
    }

    console.log(`[/final-feedback] Generating final assessment...`);
    console.log(`Total questions asked: ${agent.questionCount}`);
    console.log(`Total conversation turns: ${agent.conversationHistory.length}`);
    
    const feedback = await agent.generateFinalFeedback();
    
    // Get conversation log before removing agent
    const conversationLog = agent.getConversationLog();
    
    const duration = Date.now() - startTime;
    
    console.log('\n=== FINAL FEEDBACK GENERATED ===');
    console.log(`Room: ${roomName}`);
    console.log(`Duration: ${duration}ms`);
    console.log(`Total Questions: ${agent.questionCount}`);
    console.log(`Total Interactions: ${conversationLog.length}`);
    console.log(`Feedback Length: ${feedback.length} characters`);
    console.log('\n--- FEEDBACK CONTENT ---');
    console.log(feedback);
    console.log('--- END FEEDBACK ---\n');
    console.log('===============================\n');
    
    // Save complete log to file or database if needed
    console.log('\n=== COMPLETE INTERVIEW SUMMARY ===');
    console.log(JSON.stringify({
      roomName,
      participantIdentity,
      totalQuestions: agent.questionCount,
      totalInteractions: conversationLog.length,
      duration: `${duration}ms`,
      conversationLog: conversationLog
    }, null, 2));
    console.log('=================================\n');
    
    // Remove agent after getting feedback
    removeAgent(roomName);
    console.log(`[/final-feedback] Agent removed for room: ${roomName}`);
    
    res.json({ 
      feedback,
      statistics: {
        totalQuestions: agent.questionCount,
        totalInteractions: conversationLog.length,
        interviewDuration: duration
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    const duration = Date.now() - startTime;
    
    console.error('\n=== FINAL FEEDBACK ERROR ===');
    console.error(`Duration: ${duration}ms`);
    console.error(`Error:`, error.message);
    console.error(`Stack:`, error.stack);
    console.error('===========================\n');
    
    res.status(500).json({ error: 'Failed to generate feedback' });
  }
});

// Get conversation log endpoint (optional - for debugging)
router.get('/conversation-log/:roomName', (req, res) => {
  try {
    const { roomName } = req.params;
    const agent = getAgent(roomName);

    if (!agent) {
      return res.status(404).json({ error: 'Agent not found' });
    }

    const log = agent.getConversationLog();
    
    res.json({
      roomName,
      totalEntries: log.length,
      log: log
    });
  } catch (error) {
    console.error('Error fetching conversation log:', error);
    res.status(500).json({ error: 'Failed to fetch conversation log' });
  }
});

export default router;