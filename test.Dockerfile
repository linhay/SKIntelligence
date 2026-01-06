FROM swift:6.1-noble
WORKDIR /app
COPY . .
RUN swift package clean
RUN swift build
RUN swift test
