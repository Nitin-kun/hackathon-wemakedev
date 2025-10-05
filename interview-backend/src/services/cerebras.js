import axios from 'axios';
import { RoomServiceClient, Room } from 'livekit-server-sdk';

const CEREBRAS_API_URL = 'https://api.cerebras.ai/v1/chat/completions';
const activeAgents = new Map();

class InterviewAgent {
  constructor(config) {
    this.roomName = config.roomName;
    this.role = config.role;
    this.requirements = config.requirements;
    this.resumeUrl = config.resumeUrl;
    this.githubUrl = config.githubUrl;
    this.conversationHistory = [];
    this.questionCount = 0;
    this.maxQuestions = 10; // Hidden from user
    this.conversationLog = []; // Detailed logging
  }

  async generateSystemPrompt() {
    return `You are an expert technical interviewer conducting an interview for the role: ${this.role}.

Key Requirements: ${this.requirements}
Candidate Resume: ${this.resumeUrl}
${this.githubUrl ? `GitHub Profile: ${this.githubUrl}` : ''}

Your task:
1. Conduct a natural, conversational interview - don't mention question numbers
2. Ask relevant technical and behavioral questions based on the role
3. Listen carefully to responses and ask thoughtful follow-up questions
4. Provide brief, encouraging feedback after answers
5. Make the candidate feel comfortable while assessing their skills
6. Vary between technical questions, behavioral questions, and scenario-based questions
7. Keep your questions and responses concise but natural

Important: This is a conversational interview. Never say "Question 1", "Question 2", etc. Just ask naturally.`;
  }

  logInteraction(type, content, metadata = {}) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      type,
      content,
      questionNumber: this.questionCount,
      ...metadata
    };
    this.conversationLog.push(logEntry);
    console.log('=== INTERVIEW LOG ===');
    console.log(JSON.stringify(logEntry, null, 2));
    console.log('====================\n');
  }

  async askQuestion() {
    try {
      const systemPrompt = await this.generateSystemPrompt();
      
      const messages = [
        { role: 'system', content: systemPrompt },
        ...this.conversationHistory,
        { 
          role: 'user', 
          content: this.questionCount === 0 
            ? 'Welcome the candidate warmly and ask your first question naturally. Don\'t mention it\'s "question 1".' 
            : 'Ask your next question naturally based on the conversation so far. Make it conversational.'
        }
      ];

      this.logInteraction('REQUEST_QUESTION', 'Requesting next question from AI', {
        conversationLength: this.conversationHistory.length
      });

      const response = await axios.post(
        CEREBRAS_API_URL,
        {
          model: 'llama3.1-8b',
          messages: messages,
          temperature: 0.7,
          max_tokens: 200,
          stream: false
        },
        {
          headers: {
            'Authorization': `Bearer ${process.env.CEREBRAS_API_KEY}`,
            'Content-Type': 'application/json'
          }
        }
      );

      const question = response.data.choices[0].message.content;
      this.conversationHistory.push(
        { role: 'assistant', content: question }
      );
      this.questionCount++;

      this.logInteraction('AI_QUESTION', question, {
        model: 'llama3.1-8b',
        tokens: response.data.usage
      });

      return question;
    } catch (error) {
      this.logInteraction('ERROR', 'Failed to generate question', {
        error: error.response?.data || error.message
      });
      console.error('Cerebras API error:', error.response?.data || error.message);
      throw error;
    }
  }

  async provideFeedback(candidateResponse) {
    try {
      this.logInteraction('CANDIDATE_RESPONSE', candidateResponse, {
        responseLength: candidateResponse.length
      });

      const messages = [
        { role: 'system', content: await this.generateSystemPrompt() },
        ...this.conversationHistory,
        { role: 'user', content: candidateResponse }
      ];

      this.logInteraction('REQUEST_FEEDBACK', 'Requesting feedback from AI');

      const response = await axios.post(
        CEREBRAS_API_URL,
        {
          model: 'llama3.1-8b',
          messages: messages,
          temperature: 0.6,
          max_tokens: 150
        },
        {
          headers: {
            'Authorization': `Bearer ${process.env.CEREBRAS_API_KEY}`,
            'Content-Type': 'application/json'
          }
        }
      );

      const feedback = response.data.choices[0].message.content;
      this.conversationHistory.push(
        { role: 'user', content: candidateResponse },
        { role: 'assistant', content: feedback }
      );

      this.logInteraction('AI_FEEDBACK', feedback, {
        tokens: response.data.usage
      });

      return feedback;
    } catch (error) {
      this.logInteraction('ERROR', 'Failed to generate feedback', {
        error: error.response?.data || error.message
      });
      console.error('Feedback generation error:', error);
      return 'Thank you for that answer. Let\'s continue.';
    }
  }

  async generateFinalFeedback() {
    try {
      this.logInteraction('REQUEST_FINAL_FEEDBACK', 'Generating final interview assessment');

      const messages = [
        { role: 'system', content: await this.generateSystemPrompt() },
        ...this.conversationHistory,
        { 
          role: 'user', 
          content: `Provide comprehensive final feedback on the candidate's overall performance. Include:
          1. Overall impression and key strengths
          2. Areas for improvement
          3. Technical competency assessment
          4. Communication and soft skills
          5. A rating out of 10 with justification
          6. Hiring recommendation (Strong Yes / Yes / Maybe / No)
          
          Be constructive, specific, and professional.`
        }
      ];

      const response = await axios.post(
        CEREBRAS_API_URL,
        {
          model: 'llama3.1-8b',
          messages: messages,
          temperature: 0.5,
          max_tokens: 500
        },
        {
          headers: {
            'Authorization': `Bearer ${process.env.CEREBRAS_API_KEY}`,
            'Content-Type': 'application/json'
          }
        }
      );

      const finalFeedback = response.data.choices[0].message.content;
      
      this.logInteraction('FINAL_FEEDBACK', finalFeedback, {
        totalQuestions: this.questionCount,
        totalInteractions: this.conversationLog.length,
        tokens: response.data.usage
      });

      console.log('\n=== COMPLETE INTERVIEW LOG ===');
      console.log(JSON.stringify(this.conversationLog, null, 2));
      console.log('=============================\n');

      return finalFeedback;
    } catch (error) {
      this.logInteraction('ERROR', 'Failed to generate final feedback', {
        error: error.response?.data || error.message
      });
      console.error('Final feedback error:', error);
      return 'Interview completed. Thank you for your participation.';
    }
  }

  getConversationLog() {
    return this.conversationLog;
  }
}

export async function startInterviewAgent(config) {
  const agent = new InterviewAgent(config);
  activeAgents.set(config.roomName, agent);

  agent.logInteraction('INTERVIEW_STARTED', 'New interview session created', {
    role: config.role,
    roomName: config.roomName
  });

  // Wait for user to connect
  setTimeout(async () => {
    try {
      const firstQuestion = await agent.askQuestion();
      console.log('First question:', firstQuestion);
    } catch (error) {
      console.error('Failed to start interview:', error);
    }
  }, 3000);

  return agent;
}

export function getAgent(roomName) {
  return activeAgents.get(roomName);
}

export function removeAgent(roomName) {
  const agent = activeAgents.get(roomName);
  if (agent) {
    agent.logInteraction('INTERVIEW_ENDED', 'Interview session terminated');
  }
  activeAgents.delete(roomName);
}

export default { startInterviewAgent, getAgent, removeAgent };