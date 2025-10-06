package handler;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.simpleemail.AmazonSimpleEmailService;
import com.amazonaws.services.simpleemail.AmazonSimpleEmailServiceClientBuilder;
import com.amazonaws.services.simpleemail.model.*;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.StringWriter;
import java.io.PrintWriter;
import java.util.HashMap;
import java.util.Map;

public class CommentHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final String ADMIN_EMAIL = System.getenv("ADMIN_EMAIL");
    private static final String FROM_EMAIL = System.getenv("FROM_EMAIL");
    private static final String REGION = System.getenv("DEFAULT_REGION");
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        context.getLogger().log("Lambda invoked with input: " + input + "\n");

        // Handle CORS preflight (OPTIONS) request
        String method = (String) input.get("httpMethod");
        if ("OPTIONS".equalsIgnoreCase(method)) {
            context.getLogger().log("Handling CORS preflight request.\n");
            return corsResponse(200, "CORS preflight OK");
        }

        // Extract comment from body
        String comment = extractComment(input);
        if (comment == null || comment.isBlank()) {
            return corsResponse(400, "Missing or empty 'comment' field in request body.");
        }

        try {
            context.getLogger().log("Preparing to send email from " + FROM_EMAIL + " to " + ADMIN_EMAIL + "\n");
            sendEmail(comment, context);
            return corsResponse(200, "Comment sent successfully to admin.");
        } catch (Exception e) {
            logException(e, context);
            return corsResponse(500, "Failed to send comment. " + e.getMessage());
        }
    }

    private void sendEmail(String comment, Context context) {
        AmazonSimpleEmailService client = AmazonSimpleEmailServiceClientBuilder.standard()
                .withRegion(REGION)
                .build();

        SendEmailRequest request = new SendEmailRequest()
                .withDestination(new Destination().withToAddresses(ADMIN_EMAIL))
                .withMessage(new Message()
                        .withSubject(new Content().withCharset("UTF-8").withData("New User Comment"))
                        .withBody(new Body().withText(new Content().withCharset("UTF-8").withData(comment))))
                .withSource(FROM_EMAIL);

        context.getLogger().log("Sending email via SES in region: " + REGION + "\n");

        try {
            SendEmailResult result = client.sendEmail(request);
            context.getLogger().log("SES Message ID: " + result.getMessageId() + "\n");
        } catch (MessageRejectedException e) {
            throw new RuntimeException("SES rejected the message: " + e.getMessage());
        } catch (MailFromDomainNotVerifiedException e) {
            throw new RuntimeException("FROM_EMAIL domain is not verified in SES: " + e.getMessage());
        } catch (ConfigurationSetDoesNotExistException e) {
            throw new RuntimeException("SES configuration set issue: " + e.getMessage());
        } catch (Exception e) {
            throw new RuntimeException("Unexpected SES error: " + e.getMessage(), e);
        }
    }

    private String extractComment(Map<String, Object> input) {
        try {
            Object bodyObj = input.get("body");
            if (bodyObj instanceof String) {
                Map<String, Object> bodyMap = OBJECT_MAPPER.readValue((String) bodyObj, Map.class);
                Object commentObj = bodyMap.get("comment");
                if (commentObj instanceof String) {
                    return (String) commentObj;
                }
            }
        } catch (Exception e) {
            // Ignore parsing errors, return null
        }
        return null;
    }

    // Adds proper CORS headers to every response
    private Map<String, Object> corsResponse(int statusCode, String message) {
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("message", message);

        Map<String, String> headers = new HashMap<>();
        headers.put("Content-Type", "application/json");
        headers.put("Access-Control-Allow-Origin", "*");
        headers.put("Access-Control-Allow-Methods", "OPTIONS,POST,GET");
        headers.put("Access-Control-Allow-Headers", "Content-Type");

        Map<String, Object> response = new HashMap<>();
        response.put("statusCode", statusCode);
        response.put("headers", headers);
        try {
            response.put("body", OBJECT_MAPPER.writeValueAsString(bodyMap));
        } catch (Exception e) {
            response.put("body", "{\"message\":\"Failed to serialize response body\"}");
        }
        return response;
    }

    private void logException(Exception e, Context context) {
        StringWriter sw = new StringWriter();
        e.printStackTrace(new PrintWriter(sw));
        context.getLogger().log("Error: " + e.getMessage() + "\n" + sw + "\n");
    }
}
