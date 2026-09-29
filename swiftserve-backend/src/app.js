const express = require('express');
const cors = require('cors');

require('./config/firebase');

const testRoutes = require('./routes/testRoutes');
const userRoutes = require('./routes/userRoutes');

const app = express();

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({
    message: 'SwiftServe backend is running!',
  });
});

app.use('/api/test', testRoutes);
app.use('/api/users', userRoutes);

module.exports = app;