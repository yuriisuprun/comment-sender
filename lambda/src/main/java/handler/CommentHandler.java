package handler;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.simpleemail.AmazonSimpleEmailService;
import com.amazonaws.services.simpleemail.AmazonSimpleEmailServiceClientBuilder;
import com.amazonaws.services.simpleemail.model.*;

import java.io.StringWriter;
import java.io.PrintWriter;
import java.util.HashMap;
import java.util.Map;

public class CommentHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final String ADMIN_EMAIL = System.getenv("ADMIN_EMAIL");
    private static final String FROM_EMAIL = System.getenv("FROM_EMAIL");
    private static final String REGION = System.getenv("DEFAULT_REGION");

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        context.getLogger().log("Lambda invoked with input: " + input + "\n");

        String comment = extractComment(input);
        if (comment == null || comment.isBlank()) {
            return response(400, "Missing or empty 'comment' field in request body.");
        }

        try {
            context.getLogger().log("Preparing to send email from " + FROM_EMAIL + " to " + ADMIN_EMAIL + "\n");
            sendEmail(comment, context);
            return response(200, "Comment sent successfully to admin.");
        } catch (Exception e) {
            logException(e, context);
            return response(500, "Failed to send comment. " + e.getMessage());
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
        Object commentObj = input.get("comment");
        if (commentObj instanceof String) {
            return (String) commentObj;
        }
        return null;
    }

    private Map<String, Object> response(int statusCode, String message) {
        Map<String, Object> body = new HashMap<>();
        body.put("message", message);

        Map<String, Object> response = new HashMap<>();
        response.put("statusCode", statusCode);
        response.put("headers", Map.of("Content-Type", "application/json"));
        response.put("body", body);
        return response;
    }

    private void logException(Exception e, Context context) {
        StringWriter sw = new StringWriter();
        e.printStackTrace(new PrintWriter(sw));
        context.getLogger().log("Error: " + e.getMessage() + "\n" + sw + "\n");
    }
}
