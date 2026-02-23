function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // If URI ends with '/' append index.html
  if (uri.endsWith('/')) {
    request.uri += 'index.html';
  }
  // If URI does not have a file extension, append /index.html
  else if (!uri.includes('.')) {
    request.uri += '/index.html';
  }

  return request;
}
