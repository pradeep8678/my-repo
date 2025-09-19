const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.send('Hello World from Pradeepssd App!');
});

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));


